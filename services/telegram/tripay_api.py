#!/usr/bin/env python3
# ============================================================
#   ZV-Manager - Tripay API Helper
#   Handles: create transaction QRIS, validate webhook signature
# ============================================================

import hashlib
import hmac
import json
import time
import urllib.request
import urllib.parse
from pathlib import Path

# ── Config loader ────────────────────────────────────────────
def load_tripay_conf() -> dict:
    conf = {}
    try:
        with open("/etc/zv-manager/tripay.conf") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, _, v = line.partition("=")
                    conf[k.strip()] = v.strip().strip('"').strip("'")
    except Exception:
        pass
    return conf

_CONF = load_tripay_conf()

API_KEY       = _CONF.get("TRIPAY_API_KEY", "")
PRIVATE_KEY   = _CONF.get("TRIPAY_PRIVATE_KEY", "")
MERCHANT_CODE = _CONF.get("TRIPAY_MERCHANT_CODE", "")
MODE          = _CONF.get("TRIPAY_MODE", "sandbox")   # sandbox | production
FEE_CUSTOMER  = _CONF.get("TRIPAY_FEE_CUSTOMER", "0") == "1"  # 1=customer tanggung fee

BASE_URL = (
    "https://tripay.co.id/api"
    if MODE == "production"
    else "https://tripay.co.id/api-sandbox"
)

# ── Pending transaction store ─────────────────────────────────
# Format: {merchant_ref: {uid, amount, created_at}}
PENDING_FILE = "/var/lib/zv-manager/tripay_pending.json"

def _load_pending() -> dict:
    try:
        return json.loads(Path(PENDING_FILE).read_text())
    except Exception:
        return {}

def _save_pending(data: dict):
    Path(PENDING_FILE).parent.mkdir(parents=True, exist_ok=True)
    Path(PENDING_FILE).write_text(json.dumps(data, indent=2))

def pending_set(merchant_ref: str, uid: int, amount: int):
    data = _load_pending()
    # Bersihkan pending yang sudah lebih dari 24 jam
    now = int(time.time())
    data = {k: v for k, v in data.items()
            if now - v.get("created_at", 0) < 86400}
    data[merchant_ref] = {"uid": uid, "amount": amount, "created_at": now}
    _save_pending(data)

def pending_get(merchant_ref: str) -> dict | None:
    return _load_pending().get(merchant_ref)

def pending_remove(merchant_ref: str):
    data = _load_pending()
    data.pop(merchant_ref, None)
    _save_pending(data)

# ── Signature ────────────────────────────────────────────────
def make_signature(merchant_ref: str, amount: int) -> str:
    """Signature untuk create transaction: HMAC-SHA256(merchant_code + merchant_ref + amount)"""
    raw = f"{MERCHANT_CODE}{merchant_ref}{amount}"
    return hmac.new(
        PRIVATE_KEY.encode(),
        raw.encode(),
        hashlib.sha256
    ).hexdigest()

def verify_webhook_signature(raw_body: bytes, received_sig: str) -> bool:
    """Validasi signature dari callback Tripay."""
    expected = hmac.new(
        PRIVATE_KEY.encode(),
        raw_body,
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, received_sig)

# ── API request helper ────────────────────────────────────────
def _post(endpoint: str, payload: dict) -> dict:
    url  = f"{BASE_URL}{endpoint}"
    body = json.dumps(payload).encode()
    req  = urllib.request.Request(
        url, data=body,
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type":  "application/json",
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body_err = e.read().decode(errors="ignore")
        try:
            return json.loads(body_err)
        except Exception:
            return {"success": False, "message": str(e)}
    except Exception as e:
        return {"success": False, "message": str(e)}

# ── Hitung fee QRIS ──────────────────────────────────────────
def calc_fee(amount: int) -> int:
    """Fee QRIS: flat 750 + 0.7% dari amount."""
    return 750 + int(amount * 0.007)

def amount_with_fee(amount: int) -> int:
    """Total yang dibayar customer jika fee ditanggung customer."""
    return amount + calc_fee(amount) if FEE_CUSTOMER else amount

# ── Create transaksi QRIS ────────────────────────────────────
def create_qris_transaction(uid: int, amount: int, domain: str) -> dict:
    """
    Buat transaksi QRIS di Tripay.
    Return dict dengan key: success, merchant_ref, qr_url, qr_string, expired_time, message
    """
    merchant_ref = f"ZV-{uid}-{int(time.time())}"
    pay_amount   = amount_with_fee(amount)
    signature    = make_signature(merchant_ref, pay_amount)
    expired_time = int(time.time()) + 3600  # 1 jam

    payload = {
        "method":         "QRIS",
        "merchant_ref":   merchant_ref,
        "amount":         pay_amount,
        "customer_name":  f"User {uid}",
        "customer_email": f"{uid}@zv.local",
        "customer_phone": "08000000000",
        "order_items": [{
            "sku":      "TOPUP",
            "name":     f"Top Up Saldo ZV-Manager",
            "price":    pay_amount,
            "quantity": 1,
        }],
        "callback_url": f"https://{domain}/tripay/callback",
        "return_url":   f"https://{domain}",
        "expired_time": expired_time,
        "signature":    signature,
    }

    resp = _post("/transaction/create", payload)

    if not resp.get("success"):
        return {"success": False, "message": resp.get("message", "Gagal buat transaksi")}

    data = resp.get("data", {})
    pending_set(merchant_ref, uid, amount)

    return {
        "success":      True,
        "merchant_ref": merchant_ref,
        "qr_url":       data.get("qr_url", ""),
        "qr_string":    data.get("qr_string", ""),
        "expired_time": expired_time,
        "pay_amount":   pay_amount,
        "fee":          calc_fee(amount) if FEE_CUSTOMER else 0,
    }
