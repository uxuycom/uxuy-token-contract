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
	"strings"
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
	flag.Parse()
	if *factoryS == "" || *deployerS == "" || (*prefix == "" && *suffix == "") {
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
			for atomic.LoadInt64(&found) < int64(*count) {
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
