package db

import (
	"fmt"
	"net"
	"os"
	"time"

	"golang.org/x/crypto/ssh"
)

// sshDialer implements pq.Dialer by opening every database connection
// through an SSH client, so no separate `ssh -L` tunnel is needed.
type sshDialer struct {
	client *ssh.Client
}

func (d sshDialer) Dial(network, address string) (net.Conn, error) {
	return d.client.Dial(network, address)
}

func (d sshDialer) DialTimeout(network, address string, _ time.Duration) (net.Conn, error) {
	return d.client.Dial(network, address)
}

// newSSHDialer connects to the SSH server described by the SSH_* variables.
// Authentication uses SSH_KEY (path to a private key) and/or SSH_PASSWORD.
func newSSHDialer(host string) (sshDialer, error) {
	port := getenv("SSH_PORT", "22")
	user := os.Getenv("SSH_USER")
	if user == "" {
		return sshDialer{}, fmt.Errorf("SSH_HOST is set but SSH_USER is empty")
	}

	var auth []ssh.AuthMethod
	if keyPath := os.Getenv("SSH_KEY"); keyPath != "" {
		key, err := os.ReadFile(keyPath)
		if err != nil {
			return sshDialer{}, fmt.Errorf("read SSH_KEY: %w", err)
		}
		var signer ssh.Signer
		if phrase := os.Getenv("SSH_KEY_PASSPHRASE"); phrase != "" {
			signer, err = ssh.ParsePrivateKeyWithPassphrase(key, []byte(phrase))
		} else {
			signer, err = ssh.ParsePrivateKey(key)
		}
		if err != nil {
			return sshDialer{}, fmt.Errorf("parse SSH_KEY: %w", err)
		}
		auth = append(auth, ssh.PublicKeys(signer))
	}
	if pass := os.Getenv("SSH_PASSWORD"); pass != "" {
		auth = append(auth, ssh.Password(pass))
	}
	if len(auth) == 0 {
		return sshDialer{}, fmt.Errorf("SSH_HOST is set but neither SSH_KEY nor SSH_PASSWORD is")
	}

	config := &ssh.ClientConfig{
		User: user,
		Auth: auth,
		// Host key is not pinned; acceptable for a course prototype that only
		// talks to the faculty server.
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         10 * time.Second,
	}
	client, err := ssh.Dial("tcp", net.JoinHostPort(host, port), config)
	if err != nil {
		return sshDialer{}, fmt.Errorf("ssh dial %s@%s:%s: %w", user, host, port, err)
	}
	return sshDialer{client: client}, nil
}
