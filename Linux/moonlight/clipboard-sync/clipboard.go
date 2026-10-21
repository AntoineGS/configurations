package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

type Observation struct {
	Seq       uint64
	Selection Selection
	Present   bool
}
type Clipboard interface {
	Watch(context.Context) (<-chan Observation, <-chan error, error)
	Apply(context.Context, Selection) error
	Close() error
}

var errOversized = errors.New("clipboard exceeds 20 MiB limit")

func ReadLimited(r io.Reader, limit int64) ([]byte, error) {
	b, err := io.ReadAll(io.LimitReader(r, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(b)) > limit {
		return nil, errOversized
	}
	return b, nil
}
func ChooseMIME(types []string) (string, bool) {
	for _, want := range []string{pngMIME, textMIME, "text/plain;charset=UTF-8", "UTF8_STRING", "text/plain"} {
		for _, offered := range types {
			if want == offered {
				return offered, true
			}
		}
	}
	return "", false
}
func DesktopEnvironment(raw string) (map[string]string, error) {
	env := make(map[string]string)
	for _, line := range strings.Split(raw, "\n") {
		k, v, ok := strings.Cut(line, "=")
		if !ok || k != "WAYLAND_DISPLAY" && k != "XDG_RUNTIME_DIR" {
			continue
		}
		if strings.ContainsAny(v, "\x00\r") || v == "" {
			return nil, errors.New("invalid graphical session environment")
		}
		env[k] = v
	}
	if env["WAYLAND_DISPLAY"] == "" || !filepath.IsAbs(env["XDG_RUNTIME_DIR"]) {
		return nil, errors.New("no graphical Wayland session")
	}
	return env, nil
}
func SelectionHash(s Selection) [32]byte {
	h := sha256.New()
	h.Write([]byte(s.MIME))
	h.Write([]byte{0})
	h.Write(s.Data)
	var b [32]byte
	copy(b[:], h.Sum(nil))
	return b
}

type WaylandClipboard struct {
	socket   string
	conn     *net.UnixConn
	events   chan Observation
	errs     chan error
	stop     chan struct{}
	once     sync.Once
	mu       sync.Mutex
	pending  *[32]byte
	applied  chan struct{}
	seq      uint64
	lastHash [32]byte
	hasLast  bool
}

func NewWaylandClipboard(socket string) *WaylandClipboard {
	return &WaylandClipboard{socket: socket, events: make(chan Observation, 1), errs: make(chan error, 1), stop: make(chan struct{})}
}
func (c *WaylandClipboard) Close() error {
	var err error
	c.once.Do(func() {
		close(c.stop)
		if c.conn != nil {
			err = c.conn.Close()
		}
	})
	return err
}

func (c *WaylandClipboard) Watch(ctx context.Context) (<-chan Observation, <-chan error, error) {
	conn, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: c.socket, Net: "unix"})
	if err != nil {
		return nil, nil, err
	}
	c.conn = conn
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	fail := func(err error) (<-chan Observation, <-chan error, error) { c.Close(); return nil, nil, err }
	// IDs: display=1, registry=2, sync=3, manager=4, seat=5, device=6, sync=7.
	if err = writeWL(conn, 1, 1, wlUint(2), -1); err != nil {
		return fail(err)
	}
	if err = writeWL(conn, 1, 0, wlUint(3), -1); err != nil {
		return fail(err)
	}
	var manager, seat uint32
	for {
		id, op, b, err := readWL(conn)
		if err != nil {
			return fail(err)
		}
		if id == 3 && op == 0 {
			break
		}
		if id == 1 && op == 0 {
			return fail(errors.New("Wayland registry error"))
		}
		if id == 2 && op == 0 && len(b) >= 8 {
			iface, _, err := parseWLString(b[4:])
			if err != nil {
				return fail(err)
			}
			if iface == "zwlr_data_control_manager_v1" {
				manager = binary.NativeEndian.Uint32(b)
			}
			if iface == "wl_seat" && seat == 0 {
				seat = binary.NativeEndian.Uint32(b)
			}
		}
	}
	if manager == 0 || seat == 0 {
		return fail(errors.New("Wayland compositor lacks wlr-data-control or seat"))
	}
	for _, v := range []struct {
		name  uint32
		iface string
		id    uint32
	}{{manager, "zwlr_data_control_manager_v1", 4}, {seat, "wl_seat", 5}} {
		b := append(wlUint(v.name), wlString(v.iface)...)
		b = append(b, wlUint(1)...)
		b = append(b, wlUint(v.id)...)
		if err = writeWL(conn, 2, 0, b, -1); err != nil {
			return fail(err)
		}
	}
	if err = writeWL(conn, 4, 1, append(wlUint(6), wlUint(5)...), -1); err != nil {
		return fail(err)
	}
	if err = writeWL(conn, 1, 0, wlUint(7), -1); err != nil {
		return fail(err)
	}
	offers := make(map[uint32][]string)
	for {
		id, op, b, err := readWL(conn)
		if err != nil {
			return fail(err)
		}
		if id == 7 && op == 0 {
			break
		}
		if err = c.event(id, op, b, offers, false); err != nil {
			return fail(err)
		}
	}
	conn.SetDeadline(time.Time{})
	go func() {
		select {
		case <-ctx.Done():
			c.Close()
		case <-c.stop:
		}
	}()
	go func() {
		defer c.Close()
		for {
			id, op, b, err := readWL(conn)
			if err == nil {
				err = c.event(id, op, b, offers, true)
			}
			if err != nil {
				select {
				case c.errs <- err:
				default:
				}
				return
			}
		}
	}()
	return c.events, c.errs, nil
}

func (c *WaylandClipboard) event(id uint32, op uint16, b []byte, offers map[uint32][]string, armed bool) error {
	if id == 1 && op == 0 {
		return errors.New("Wayland data-control error")
	}
	if id == 6 {
		if op == 2 {
			return errors.New("Wayland data-control finished")
		}
		if op > 1 {
			return nil
		}
		if len(b) != 4 {
			return errors.New("invalid data-control event")
		}
		offer := binary.NativeEndian.Uint32(b)
		if op == 0 {
			if len(offers) >= 64 {
				return errors.New("too many clipboard offers")
			}
			offers[offer] = nil
			return nil
		}
		if offer == 0 {
			return nil
		}
		types, ok := offers[offer]
		if !ok {
			return errors.New("unknown clipboard offer")
		}
		delete(offers, offer)
		defer writeWL(c.conn, offer, 1, nil, -1)
		mime, supported := ChooseMIME(types)
		if !armed || !supported {
			return nil
		}
		r, w, err := os.Pipe()
		if err != nil {
			return err
		}
		defer r.Close()
		err = writeWL(c.conn, offer, 0, wlString(mime), int(w.Fd()))
		w.Close()
		if err != nil {
			return err
		}
		r.SetReadDeadline(time.Now().Add(5 * time.Second))
		data, err := ReadLimited(r, MaxPayload)
		if err != nil {
			if errors.Is(err, errOversized) {
				notify("Clipboard copy exceeds 20 MiB; skipped.")
			}
			return nil
		}
		if mime != pngMIME {
			if !utf8.Valid(data) {
				return nil
			}
			mime = textMIME
		}
		c.observe(Selection{MIME: mime, Data: data})
		return nil
	}
	if types, ok := offers[id]; ok && op == 0 {
		mime, _, err := parseWLString(b)
		if err != nil {
			return err
		}
		if len(types) >= 64 {
			return errors.New("too many MIME types")
		}
		offers[id] = append(types, mime)
	}
	return nil
}

func (c *WaylandClipboard) observe(s Selection) {
	hash := SelectionHash(s)
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.pending != nil && *c.pending == hash {
		c.pending = nil
		c.lastHash, c.hasLast = hash, true
		close(c.applied)
		return
	}
	if c.hasLast && c.lastHash == hash {
		return
	}
	c.lastHash, c.hasLast = hash, true
	c.seq++
	e := Observation{Seq: c.seq, Selection: s, Present: true}
	select {
	case c.events <- e:
	default:
		select {
		case <-c.events:
		default:
		}
		c.events <- e
	}
}

func (c *WaylandClipboard) Apply(ctx context.Context, s Selection) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	hash := SelectionHash(s)
	c.mu.Lock()
	c.pending = &hash
	c.applied = make(chan struct{})
	done := c.applied
	c.mu.Unlock()
	cmd := exec.CommandContext(ctx, "/usr/bin/wl-copy", "--type", s.MIME)
	cmd.Env = append(os.Environ(), "WAYLAND_DISPLAY="+c.socket)
	cmd.Stdin = bytes.NewReader(s.Data)
	if err := cmd.Run(); err != nil {
		return errors.New("cannot set desktop clipboard")
	}
	select {
	case <-done:
		return nil
	case <-c.stop:
		return errors.New("clipboard observer stopped")
	case <-ctx.Done():
		return errors.New("clipboard ownership confirmation timed out")
	}
}
