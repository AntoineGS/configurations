package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"unicode/utf8"
)

const (
	MaxPayload  = 20 << 20
	MaxMetadata = 4096
	wireMagic   = "MCLIP001"
	textMIME    = "text/plain;charset=utf-8"
	pngMIME     = "image/png"
)

type Selection struct {
	MIME string
	Data []byte
}

type Frame struct {
	Kind     string `json:"kind"`
	Seq      uint64 `json:"seq,omitempty"`
	Base     uint64 `json:"base,omitempty"`
	Revision uint64 `json:"revision,omitempty"`
	MIME     string `json:"mime,omitempty"`
	Code     string `json:"code,omitempty"`
	Data     []byte `json:"-"`
}

var errFrame = errors.New("invalid clipboard protocol frame")

// Validate metadata separately, before allocating or reading any payload.
func (f Frame) validateMetadata(size int) error {
	if size < 0 || size > MaxPayload {
		return errFrame
	}
	switch f.Kind {
	case "proposal", "apply":
		if f.MIME != textMIME && f.MIME != pngMIME || f.Code != "" {
			return errFrame
		}
		if f.Kind == "proposal" && (f.Seq == 0 || f.Revision != 0) {
			return errFrame
		}
		if f.Kind == "apply" && (f.Revision == 0 || f.Base != 0) {
			return errFrame
		}
	case "hello", "ready", "ping", "pong", "ack", "error":
		if size != 0 || f.MIME != "" || f.Base != 0 {
			return errFrame
		}
		if f.Kind == "ack" {
			if f.Revision == 0 || f.Code != "" {
				return errFrame
			}
		} else {
			if f.Seq != 0 || f.Revision != 0 {
				return errFrame
			}
			if f.Kind == "error" {
				switch f.Code {
				case "busy", "unavailable", "protocol", "capture", "apply", "oversized":
				default:
					return errFrame
				}
			} else if f.Code != "" {
				return errFrame
			}
		}
	default:
		return errFrame
	}
	return nil
}

func ReadFrame(r io.Reader) (Frame, error) {
	var header [16]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		return Frame{}, err
	}
	metaSize := binary.BigEndian.Uint32(header[8:12])
	dataSize := binary.BigEndian.Uint32(header[12:16])
	if string(header[:8]) != wireMagic || metaSize == 0 || metaSize > MaxMetadata || dataSize > MaxPayload {
		return Frame{}, errFrame
	}
	metadata := make([]byte, int(metaSize))
	if _, err := io.ReadFull(r, metadata); err != nil {
		return Frame{}, err
	}
	var f Frame
	decoder := json.NewDecoder(bytes.NewReader(metadata))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&f); err != nil {
		return Frame{}, errFrame
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return Frame{}, errFrame
	}
	if err := f.validateMetadata(int(dataSize)); err != nil {
		return Frame{}, err
	}
	f.Data = make([]byte, int(dataSize))
	if _, err := io.ReadFull(r, f.Data); err != nil {
		return Frame{}, err
	}
	if f.MIME == textMIME && !utf8.Valid(f.Data) {
		return Frame{}, errFrame
	}
	return f, nil
}

func WriteFrame(w io.Writer, f Frame) error {
	if err := f.validateMetadata(len(f.Data)); err != nil {
		return err
	}
	if f.MIME == textMIME && !utf8.Valid(f.Data) {
		return errFrame
	}
	metadata, err := json.Marshal(f)
	if err != nil {
		return errFrame
	}
	if len(metadata) > MaxMetadata {
		return errFrame
	}
	var header [16]byte
	copy(header[:8], wireMagic)
	binary.BigEndian.PutUint32(header[8:12], uint32(len(metadata)))
	binary.BigEndian.PutUint32(header[12:16], uint32(len(f.Data)))
	for _, chunk := range [][]byte{header[:], metadata, f.Data} {
		for len(chunk) > 0 {
			n, err := w.Write(chunk)
			if err != nil {
				return err
			}
			if n <= 0 || n > len(chunk) {
				return io.ErrShortWrite
			}
			chunk = chunk[n:]
		}
	}
	return nil
}
