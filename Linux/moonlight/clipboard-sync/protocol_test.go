package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"io"
	"testing"
)

// These checks catch binary corruption, frame-boundary loss and unsafe allocation.
func TestFrameRoundTrip(t *testing.T) {
	frames := []Frame{
		{Kind: "hello"},
		{Kind: "proposal", Seq: 1, MIME: "image/png", Data: []byte{0, 255, 10, 0}},
		{Kind: "apply", Revision: 1, MIME: "text/plain;charset=utf-8", Data: []byte("é\n\n")},
		{Kind: "proposal", Seq: 2, MIME: "text/plain;charset=utf-8", Data: []byte{}},
		{Kind: "ack", Revision: 1},
	}
	var b bytes.Buffer
	for _, f := range frames {
		if err := WriteFrame(&b, f); err != nil {
			t.Fatal(err)
		}
	}
	for _, want := range frames {
		got, err := ReadFrame(&b)
		if err != nil {
			t.Fatal(err)
		}
		if got.Kind != want.Kind || got.Seq != want.Seq || got.Revision != want.Revision || got.MIME != want.MIME || !bytes.Equal(got.Data, want.Data) {
			t.Fatal("frame fields or binary payload changed")
		}
	}
	if _, err := ReadFrame(&b); !errors.Is(err, io.EOF) {
		t.Fatalf("expected EOF, got %v", err)
	}
}

func packet(meta string, body []byte) []byte {
	b := make([]byte, 16)
	copy(b, "MCLIP001")
	binary.BigEndian.PutUint32(b[8:12], uint32(len(meta)))
	binary.BigEndian.PutUint32(b[12:16], uint32(len(body)))
	return append(append(b, meta...), body...)
}

func TestReadFrameRejectsMalformed(t *testing.T) {
	valid := packet(`{"kind":"proposal","seq":1,"mime":"image/png"}`, []byte{0, 1})
	cases := map[string][]byte{
		"banner":           append([]byte("Welcome to SSH\n"), valid...),
		"short header":     valid[:12],
		"truncated body":   valid[:len(valid)-1],
		"unknown kind":     packet(`{"kind":"unexpected"}`, nil),
		"unknown field":    packet(`{"kind":"hello","password":"hidden"}`, nil),
		"trailing JSON":    packet(`{"kind":"hello"}{}`, nil),
		"invalid MIME":     packet(`{"kind":"proposal","seq":1,"mime":"text/uri-list"}`, nil),
		"invalid UTF8":     packet(`{"kind":"proposal","seq":1,"mime":"text/plain;charset=utf-8"}`, []byte{255}),
		"control payload":  packet(`{"kind":"ping"}`, []byte{1}),
		"missing sequence": packet(`{"kind":"proposal","mime":"image/png"}`, nil),
		"missing revision": packet(`{"kind":"ack"}`, nil),
		"unknown code":     packet(`{"kind":"error","code":"unexpected"}`, nil),
	}
	version := bytes.Clone(valid)
	version[7] = '2'
	cases["version"] = version
	for name, input := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := ReadFrame(bytes.NewReader(input)); err == nil {
				t.Fatal("accepted malformed frame")
			}
		})
	}
}

type forbiddenRead struct{ t *testing.T }

func (r forbiddenRead) Read([]byte) (int, error) {
	r.t.Fatal("read body after invalid length")
	return 0, io.EOF
}

func TestReadFrameBoundsBeforeBody(t *testing.T) {
	for _, offset := range []int{8, 12} {
		header := packet("", nil)
		binary.BigEndian.PutUint32(header[offset:offset+4], ^uint32(0))
		if _, err := ReadFrame(io.MultiReader(bytes.NewReader(header), forbiddenRead{t})); err == nil {
			t.Fatal("accepted oversized frame")
		}
	}
}

type shortWriter struct{ bytes.Buffer }

func (w *shortWriter) Write(p []byte) (int, error) { return w.Buffer.Write(p[:1]) }

type zeroWriter struct{}

func (zeroWriter) Write([]byte) (int, error) { return 0, nil }

func TestWriteFrameShortWrites(t *testing.T) {
	f := Frame{Kind: "proposal", Seq: 1, MIME: "image/png", Data: []byte{0, 255}}
	var w shortWriter
	if err := WriteFrame(&w, f); err != nil {
		t.Fatal(err)
	}
	got, err := ReadFrame(&w.Buffer)
	if err != nil || !bytes.Equal(got.Data, f.Data) {
		t.Fatal("short write corrupted frame")
	}
	if err := WriteFrame(zeroWriter{}, f); !errors.Is(err, io.ErrShortWrite) {
		t.Fatalf("zero write: %v", err)
	}
}

func TestWriteFrameRejectsInvalidBeforeOutput(t *testing.T) {
	for _, f := range []Frame{
		{Kind: "proposal", Seq: 1, MIME: "image/png", Data: make([]byte, (20<<20)+1)},
		{Kind: "hello", Seq: 1},
		{Kind: "error", Code: "payload-content"},
	} {
		var b bytes.Buffer
		if err := WriteFrame(&b, f); err == nil || b.Len() != 0 {
			t.Fatal("invalid frame reached transport")
		}
	}
}
