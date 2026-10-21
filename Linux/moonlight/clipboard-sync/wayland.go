package main

import (
	"encoding/binary"
	"errors"
	"io"
	"net"
	"syscall"
)

// Only registry, display.sync and wlr-data-control v1 are used. Incoming events
// in this protocol subset contain no file descriptors. The sole outgoing FD
// is the write end of an offer.receive pipe.
func wlUint(v uint32) []byte { b := make([]byte, 4); binary.NativeEndian.PutUint32(b, v); return b }
func wlString(s string) []byte {
	b := make([]byte, 4+((len(s)+1+3)&^3))
	binary.NativeEndian.PutUint32(b, uint32(len(s)+1))
	copy(b[4:], s)
	return b
}
func parseWLString(b []byte) (string, int, error) {
	if len(b) < 4 {
		return "", 0, io.ErrUnexpectedEOF
	}
	n := int(binary.NativeEndian.Uint32(b))
	end := 4 + ((n + 3) &^ 3)
	if n < 1 || end > len(b) || b[4+n-1] != 0 {
		return "", 0, errors.New("invalid Wayland string")
	}
	return string(b[4 : 4+n-1]), end, nil
}
func readWL(r io.Reader) (uint32, uint16, []byte, error) {
	var h [8]byte
	if _, err := io.ReadFull(r, h[:]); err != nil {
		return 0, 0, nil, err
	}
	word := binary.NativeEndian.Uint32(h[4:])
	n := int(word >> 16)
	if n < 8 || n%4 != 0 {
		return 0, 0, nil, errors.New("invalid Wayland message length")
	}
	b := make([]byte, n-8)
	_, err := io.ReadFull(r, b)
	return binary.NativeEndian.Uint32(h[:4]), uint16(word), b, err
}
func writeWL(c *net.UnixConn, id uint32, op uint16, data []byte, fd int) error {
	if len(data)%4 != 0 || len(data) > 65524 {
		return errors.New("invalid Wayland request")
	}
	b := append(append(wlUint(id), wlUint(uint32(len(data)+8)<<16|uint32(op))...), data...)
	var rights []byte
	if fd >= 0 {
		rights = syscall.UnixRights(fd)
	}
	n, _, err := c.WriteMsgUnix(b, rights, nil)
	if err != nil {
		return err
	}
	for n < len(b) {
		m, err := c.Write(b[n:])
		if err != nil {
			return err
		}
		if m == 0 {
			return io.ErrShortWrite
		}
		n += m
	}
	return nil
}
