// SPDX-License-Identifier: AGPL-3.0-or-later

package notifier

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDoDispatchUsesValidCosmomailHeaders(t *testing.T) {
	t.Helper()

	var eventHeader, timestampHeader, signatureHeader string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		eventHeader = r.Header.Get(HeaderEvent)
		timestampHeader = r.Header.Get(HeaderTimestamp)
		signatureHeader = r.Header.Get(HeaderSignature)
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	payload := Payload{Event: "mail.received", Timestamp: 123, Data: map[string]interface{}{"id": 1}}
	result := doDispatch(&hookInfo{URL: server.URL, Secret: "test-secret"}, payload, payload.Event)

	if !result.Success {
		t.Fatalf("dispatch failed: %s", result.ErrorMsg)
	}
	if eventHeader != payload.Event {
		t.Fatalf("unexpected event header: %q", eventHeader)
	}
	if timestampHeader != "123" {
		t.Fatalf("unexpected timestamp header: %q", timestampHeader)
	}
	if signatureHeader == "" {
		t.Fatal("signature header was not sent")
	}
}
