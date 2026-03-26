package main

// ============================================================
//   ZV-Manager — License Checker
//   Compile: CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o zv-checker main.go
//
//   Exit code:
//     0 → IP terdaftar dan valid (atau Lifetime)
//     1 → IP tidak ditemukan di whitelist
//     2 → IP ditemukan, sudah expired tapi masih dalam grace period
//     3 → IP ditemukan, grace period habis → trigger uninstall
//     4 → Gagal fetch (koneksi gagal / repo tidak bisa diakses)
// ============================================================

import (
	"bufio"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// URL di-encode XOR agar tidak langsung terbaca di binary
// Key: 0x5A ('Z')
// URL: https://raw.githubusercontent.com/ZenXNF/zvkey/main/authorized_vps
var encodedURL = []byte{
	0x32, 0x2e, 0x2e, 0x2a, 0x29, 0x60, 0x75, 0x75, 0x28, 0x3b,
	0x2d, 0x74, 0x3d, 0x33, 0x2e, 0x32, 0x2f, 0x38, 0x2f, 0x29,
	0x3f, 0x28, 0x39, 0x35, 0x34, 0x2e, 0x3f, 0x34, 0x2e, 0x74,
	0x39, 0x35, 0x37, 0x75, 0x00, 0x3f, 0x34, 0x02, 0x14, 0x1c,
	0x75, 0x20, 0x2c, 0x31, 0x3f, 0x23, 0x75, 0x37, 0x3b, 0x33,
	0x34, 0x75, 0x3b, 0x2f, 0x2e, 0x32, 0x35, 0x28, 0x33, 0x20,
	0x3f, 0x3e, 0x05, 0x2c, 0x2a, 0x29,
}

const xorKey = 0x5A

// gracePeriodDays adalah jumlah hari toleransi setelah expired
const gracePeriodDays = 2

func decodeURL() string {
	result := make([]byte, len(encodedURL))
	for i, b := range encodedURL {
		result[i] = b ^ xorKey
	}
	return string(result)
}

func fetchWhitelist() (string, error) {
	url := decodeURL()
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

type vpsEntry struct {
	name    string
	expired string // "Lifetime" atau "YYYY-MM-DD"
	ip      string
}

func parseWhitelist(content string) []vpsEntry {
	var entries []vpsEntry
	scanner := bufio.NewScanner(strings.NewReader(content))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		// Hanya proses baris yang diawali "###"
		if !strings.HasPrefix(line, "###") {
			continue
		}
		line = strings.TrimPrefix(line, "###")
		line = strings.TrimSpace(line)
		parts := strings.Fields(line)
		if len(parts) < 3 {
			continue
		}
		entries = append(entries, vpsEntry{
			name:    parts[0],
			expired: parts[1],
			ip:      parts[2],
		})
	}
	return entries
}

func checkIP(ip string, entries []vpsEntry) (found bool, entry vpsEntry) {
	for _, e := range entries {
		if e.ip == ip {
			return true, e
		}
	}
	return false, vpsEntry{}
}

func daysUntilExpired(expiredStr string) (int, error) {
	loc, _ := time.LoadLocation("Asia/Jakarta")
	now := time.Now().In(loc)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)

	expDate, err := time.ParseInLocation("2006-01-02", expiredStr, loc)
	if err != nil {
		return 0, fmt.Errorf("format tanggal tidak valid: %s", expiredStr)
	}
	diff := int(expDate.Sub(today).Hours() / 24)
	return diff, nil
}

func getPublicIP() (string, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get("https://ipv4.icanhazip.com")
	if err != nil {
		resp, err = client.Get("https://ipinfo.io/ip")
		if err != nil {
			return "", fmt.Errorf("gagal mendapatkan IP publik")
		}
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(body)), nil
}

// outputZVInfo mencetak baris machine-readable untuk di-parse oleh core/license.sh
// Format: ##ZVINFO:name=xxx|expired=xxx|days=xxx|code=x
// Baris ini disembunyikan dari tampilan user oleh core/license.sh
func outputZVInfo(name, expired string, days, code int) {
	fmt.Printf("##ZVINFO:name=%s|expired=%s|days=%d|code=%d\n", name, expired, days, code)
}

func main() {
	// Ambil IP dari argumen atau auto-detect
	var publicIP string
	if len(os.Args) >= 2 {
		publicIP = strings.TrimSpace(os.Args[1])
	} else {
		var err error
		publicIP, err = getPublicIP()
		if err != nil {
			fmt.Println("[!] Gagal mendapatkan IP VPS:", err)
			os.Exit(4)
		}
	}

	// Fetch whitelist dari zvkey
	content, err := fetchWhitelist()
	if err != nil {
		fmt.Println("[!] Gagal mengakses daftar izin:", err)
		os.Exit(4)
	}

	entries := parseWhitelist(content)
	found, entry := checkIP(publicIP, entries)

	if !found {
		fmt.Println("")
		fmt.Println("  ╔══════════════════════════════════════╗")
		fmt.Println("  ║         AKSES DITOLAK ✗              ║")
		fmt.Println("  ╚══════════════════════════════════════╝")
		fmt.Println("")
		fmt.Printf("  IP VPS   : %s\n", publicIP)
		fmt.Println("  Status   : Tidak terdaftar")
		fmt.Println("")
		fmt.Println("  VPS ini tidak memiliki izin untuk")
		fmt.Println("  menjalankan ZV-Manager.")
		fmt.Println("")
		fmt.Println("  Silahkan hubungi Telegram: @ZenXNF / t.me/ZenXNF")
		fmt.Println("")
		os.Exit(1)
	}

	// Lifetime — langsung lolos
	if strings.EqualFold(entry.expired, "Lifetime") {
		fmt.Printf("[✔] %s — Izin aktif (Seumur Hidup)\n", entry.name)
		outputZVInfo(entry.name, "Lifetime", 99999, 0)
		os.Exit(0)
	}

	// Cek tanggal expired
	daysLeft, err := daysUntilExpired(entry.expired)
	if err != nil {
		fmt.Println("[!] Format tanggal tidak valid di daftar izin:", err)
		os.Exit(4)
	}

	if daysLeft > 0 {
		// Belum expired
		if daysLeft <= 7 {
			fmt.Printf("[⚠] %s — Izin berakhir dalam %d hari (%s)\n", entry.name, daysLeft, entry.expired)
			fmt.Println("    Silahkan hubungi Telegram: @ZenXNF / t.me/ZenXNF")
		} else {
			fmt.Printf("[✔] %s — Izin aktif hingga %s (%d hari lagi)\n", entry.name, entry.expired, daysLeft)
		}
		outputZVInfo(entry.name, entry.expired, daysLeft, 0)
		os.Exit(0)
	}

	// Sudah expired — hitung grace period
	daysOver := -daysLeft
	graceRemaining := gracePeriodDays - daysOver

	if graceRemaining > 0 {
		// Masih dalam grace period
		fmt.Println("")
		fmt.Println("  ╔══════════════════════════════════════╗")
		fmt.Println("  ║      ⚠  PERINGATAN IZIN  ⚠          ║")
		fmt.Println("  ╚══════════════════════════════════════╝")
		fmt.Println("")
		fmt.Printf("  Nama     : %s\n", entry.name)
		fmt.Printf("  IP VPS   : %s\n", publicIP)
		fmt.Printf("  Expired  : %s (%d hari yang lalu)\n", entry.expired, daysOver)
		fmt.Printf("  Sisa     : %d hari sebelum dinonaktifkan\n", graceRemaining)
		fmt.Println("")
		fmt.Println("  Silahkan hubungi Telegram: @ZenXNF / t.me/ZenXNF")
		fmt.Println("")
		outputZVInfo(entry.name, entry.expired, daysLeft, 2)
		os.Exit(2)
	}

	// Grace period habis
	fmt.Println("")
	fmt.Println("  ╔══════════════════════════════════════╗")
	fmt.Println("  ║      ✗  IZIN TELAH BERAKHIR  ✗       ║")
	fmt.Println("  ╚══════════════════════════════════════╝")
	fmt.Println("")
	fmt.Printf("  Nama     : %s\n", entry.name)
	fmt.Printf("  IP VPS   : %s\n", publicIP)
	fmt.Printf("  Expired  : %s (%d hari yang lalu)\n", entry.expired, daysOver)
	fmt.Println("  Grace    : Sudah habis")
	fmt.Println("")
	fmt.Println("  ZV-Manager akan dihapus dari VPS ini.")
	fmt.Println("")
	os.Exit(3)
}
