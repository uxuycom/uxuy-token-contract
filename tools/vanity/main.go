// Vanity salt miner for UXUYDeployer (CREATE3).
//
//	address = keccak(0xd6 0x94 ++ proxy ++ 0x01)[12:]
//	proxy   = keccak(0xff ++ factory ++ keccak(deployer ++ salt) ++ PROXY_INITCODE_HASH)[12:]
//
// Only `salt` is searched. The deployer key is never touched.
//
//	go run . -factory 0x... -deployer 0x... -prefix 0000 -suffix uxuy
//
// Matching is case-insensitive hex; use -checksum to also require the EIP-55 casing to match
// the pattern exactly as typed (e.g. -prefix ABCD -checksum).
package main

import (
	"crypto/rand"
	"encoding/binary"
	"encoding/hex"
	"flag"
	"fmt"
	"os"
	"runtime"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/crypto/sha3"
)

const proxyInitcodeHashHex = "21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f"

func mustHex(s string, n int) []byte {
	b, err := hex.DecodeString(strings.TrimPrefix(strings.ToLower(s), "0x"))
	if err != nil || len(b) != n {
		fmt.Fprintf(os.Stderr, "bad hex %q (want %d bytes)\n", s, n)
		os.Exit(2)
	}
	return b
}

func checksum(addr []byte) string {
	lower := hex.EncodeToString(addr)
	h := sha3.NewLegacyKeccak256()
	h.Write([]byte(lower))
	hash := h.Sum(nil)
	out := []byte(lower)
	for i := 0; i < 40; i++ {
		nib := hash[i/2]
		if i%2 == 0 {
			nib >>= 4
		} else {
			nib &= 0xf
		}
		if nib >= 8 && out[i] >= 'a' && out[i] <= 'f' {
			out[i] -= 32
		}
	}
	return string(out)
}

func main() {
	factoryS := flag.String("factory", "", "UXUYDeployer address (same on all chains)")
	deployerS := flag.String("deployer", "", "EOA that will call deploy()")
	prefix := flag.String("prefix", "", "required hex prefix (after 0x)")
	suffix := flag.String("suffix", "", "required hex suffix")
	useChecksum := flag.Bool("checksum", false, "pattern must also match EIP-55 casing")
	count := flag.Int("count", 1, "stop after this many matches")
	threads := flag.Int("threads", runtime.NumCPU(), "worker goroutines")
	explore := flag.Duration("explore", 0, "explore mode: run this long, collect every address scoring >= -minbits, print sorted")
	minBits := flag.Int("minbits", 28, "explore mode: minimum rarity score in bits (28 ≈ 1 hit per 268M tries)")
	flag.Parse()
	if *factoryS == "" || *deployerS == "" {
		flag.Usage()
		os.Exit(2)
	}
	if *explore == 0 && *prefix == "" && *suffix == "" {
		flag.Usage()
		os.Exit(2)
	}
	factory := mustHex(*factoryS, 20)
	deployer := mustHex(*deployerS, 20)
	proxyHash := mustHex(proxyInitcodeHashHex, 32)
	for _, c := range strings.ToLower(*prefix + *suffix) {
		if !strings.ContainsRune("0123456789abcdef", c) {
			fmt.Fprintf(os.Stderr, "pattern must be hex, got %q\n", c)
			os.Exit(2)
		}
	}
	pLow, sLow := strings.ToLower(*prefix), strings.ToLower(*suffix)

	var tries uint64
	var found int64
	results := make(chan [2]string, 16)
	start := time.Now()
	exploring := *explore > 0
	var mu sync.Mutex
	var hits []hit
	deadline := start.Add(*explore)
	stop := func() bool {
		if exploring {
			return time.Now().After(deadline)
		}
		return atomic.LoadInt64(&found) >= int64(*count)
	}

	for w := 0; w < *threads; w++ {
		go func() {
			var seed [24]byte
			rand.Read(seed[:])
			salt := make([]byte, 32)
			copy(salt, seed[:])
			var ctr uint64
			h := sha3.NewLegacyKeccak256()
			nsBuf := make([]byte, 0, 52)
			c2Buf := make([]byte, 0, 85)
			rlpBuf := make([]byte, 0, 23)
			var ns, c2, out [32]byte
			for !stop() {
				ctr++
				binary.LittleEndian.PutUint64(salt[24:], ctr)

				h.Reset()
				nsBuf = append(append(nsBuf[:0], deployer...), salt...)
				h.Write(nsBuf)
				h.Sum(ns[:0])

				h.Reset()
				c2Buf = append(c2Buf[:0], 0xff)
				c2Buf = append(c2Buf, factory...)
				c2Buf = append(c2Buf, ns[:]...)
				c2Buf = append(c2Buf, proxyHash...)
				h.Write(c2Buf)
				h.Sum(c2[:0])

				h.Reset()
				rlpBuf = append(rlpBuf[:0], 0xd6, 0x94)
				rlpBuf = append(rlpBuf, c2[12:]...)
				rlpBuf = append(rlpBuf, 0x01)
				h.Write(rlpBuf)
				h.Sum(out[:0])

				addr := out[12:]
				if atomic.AddUint64(&tries, 1)&0xfffff == 0 {
					// progress handled by main loop
				}
				low := hex.EncodeToString(addr)
				if exploring {
					bits, why := score(low)
					if bits >= *minBits {
						cs := checksum(addr)
						mu.Lock()
						hits = append(hits, hit{bits, why, "0x" + cs, "0x" + hex.EncodeToString(salt)})
						mu.Unlock()
						fmt.Fprintf(os.Stderr, "hit %2d bits  0x%s  %s\n", bits, cs, why)
					}
					continue
				}
				if !strings.HasPrefix(low, pLow) || !strings.HasSuffix(low, sLow) {
					continue
				}
				cs := checksum(addr)
				if *useChecksum && (!strings.HasPrefix(cs, *prefix) || !strings.HasSuffix(cs, *suffix)) {
					continue
				}
				if atomic.AddInt64(&found, 1) <= int64(*count) {
					results <- [2]string{"0x" + hex.EncodeToString(salt), "0x" + cs}
				}
			}
		}()
	}

	tick := time.NewTicker(5 * time.Second)
	if exploring {
		for !stop() {
			<-tick.C
			t := atomic.LoadUint64(&tries)
			el := time.Since(start).Seconds()
			fmt.Fprintf(os.Stderr, "%.1fM tries, %.2fM/s, %d hits, %s left\n", float64(t)/1e6, float64(t)/1e6/el, len(hits), (deadline.Sub(time.Now())).Round(time.Second))
		}
		mu.Lock()
		sort.Slice(hits, func(i, j int) bool { return hits[i].bits > hits[j].bits })
		fmt.Printf("# %d hits in %.0fM tries over %s (factory %s, deployer %s)\n", len(hits), float64(atomic.LoadUint64(&tries))/1e6, explore, *factoryS, *deployerS)
		fmt.Printf("bits\taddress\tpattern\tsalt\n")
		for _, h := range hits {
			fmt.Printf("%d\t%s\t%s\t%s\n", h.bits, h.addr, h.why, h.salt)
		}
		mu.Unlock()
		return
	}
	got := 0
	for got < *count {
		select {
		case r := <-results:
			got++
			fmt.Printf("salt=%s address=%s\n", r[0], r[1])
		case <-tick.C:
			t := atomic.LoadUint64(&tries)
			el := time.Since(start).Seconds()
			fmt.Fprintf(os.Stderr, "%.1fM tries, %.2fM/s\n", float64(t)/1e6, float64(t)/1e6/el)
		}
	}
}

type hit struct {
	bits       int
	why        string
	addr, salt string
}

var words = []string{"eeee", "beef", "cafe", "face", "dead", "babe", "f00d", "c0de", "ace0", "0fee", "fade", "bead", "deaf", "feed", "0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999", "aaaa", "bbbb", "cccc", "dddd", "ffff"}

func runLen(s string, from int, step int) int {
	c := s[from]
	n := 0
	for i := from; i >= 0 && i < len(s) && s[i] == c; i += step {
		n++
	}
	return n
}

// score returns an approximate rarity in bits (log2 of expected tries) and the pattern name.
// Only patterns people actually read as "nice" are scored; everything else is 0.
func score(a string) (int, string) {
	best, why := 0, ""
	lead := runLen(a, 0, 1)
	trail := runLen(a, len(a)-1, -1)
	// leading zeros
	if a[0] == '0' && lead >= 6 {
		if b := 4 * lead; b > best {
			best, why = b, fmt.Sprintf("%d leading zeros", lead)
		}
	}
	// leading run of a non-zero char
	if a[0] != '0' && lead >= 6 {
		if b := 4*lead - 4; b > best {
			best, why = b, fmt.Sprintf("leading %dx%c", lead, a[0])
		}
	}
	// trailing run
	if trail >= 6 {
		if b := 4*trail - 4; b > best {
			best, why = b, fmt.Sprintf("trailing %dx%c", trail, a[len(a)-1])
		}
	}
	// same char run at both ends (0x8888...8888)
	if a[0] == a[len(a)-1] && lead >= 4 && trail >= 4 {
		if b := 4*(lead+trail) - 4; b > best {
			best, why = b, fmt.Sprintf("%dx%c ... %dx%c", lead, a[0], trail, a[0])
		}
	}
	// 0000 prefix + trailing run
	if strings.HasPrefix(a, "0000") && trail >= 4 && a[len(a)-1] != '0' {
		if b := 16 + 4*trail - 4; b > best {
			best, why = b, fmt.Sprintf("0000 ... %dx%c", trail, a[len(a)-1])
		}
	}
	// 0000 prefix + word suffix
	if strings.HasPrefix(a, "0000") {
		for _, w := range words {
			if strings.HasSuffix(a, w) {
				if b := 16 + 16 - 5; b > best {
					best, why = b, "0000 ... "+w
				}
			}
		}
	}
	// zeros prefix + zeros suffix (0x0000...0000)
	if lead >= 4 && trail >= 4 && a[0] == '0' && a[len(a)-1] == '0' {
		if b := 4 * (lead + trail); b > best {
			best, why = b, fmt.Sprintf("%d zeros ... %d zeros", lead, trail)
		}
	}
	return best, why
}
