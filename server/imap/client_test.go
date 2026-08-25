package imap

import "testing"

func TestRequiresClientID(t *testing.T) {
	tests := []struct {
		host string
		want bool
	}{
		{host: "imap.163.com", want: true},
		{host: " IMAP.126.COM ", want: true},
		{host: "imap.yeah.net", want: true},
		{host: "imap.qq.com", want: false},
		{host: "imap.exmail.qq.com", want: false},
		{host: "imap.gmail.com", want: false},
		{host: "outlook.office365.com", want: false},
	}

	for _, tt := range tests {
		t.Run(tt.host, func(t *testing.T) {
			if got := requiresClientID(tt.host); got != tt.want {
				t.Fatalf("requiresClientID(%q) = %v, want %v", tt.host, got, tt.want)
			}
		})
	}
}
