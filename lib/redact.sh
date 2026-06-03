# lib/redact.sh - best-effort scrub of secrets in free text.
# Operates on stdin -> stdout. Patterns ORDERED: most-specific first.

redact() {
  perl -0777 -pe '
    # PEM private key blocks (multiline) - first, before line patterns.
    s/-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/[REDACTED PRIVATE KEY]/gs;
  ' | perl -pe '
    s/\bsk-[A-Za-z0-9_\-]{20,}/sk-[REDACTED]/g;
    s/\bgh[pousar]_[A-Za-z0-9]{20,}/gh*_[REDACTED]/g;
    s/\bAKIA[0-9A-Z]{16}\b/AKIA[REDACTED]/g;
    s/\bxox[baprs]-[A-Za-z0-9-]{10,}/xox[REDACTED]/g;
    s/\beyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+/eyJ[REDACTED]/g;
    s/\bBearer\s+[A-Za-z0-9._\-]{20,}/Bearer [REDACTED]/g;
    s/\b([A-Z][A-Z0-9_]*(?:_KEY|_TOKEN|_SECRET|_PASSWORD|_PASS))\s*=\s*\S+/$1=[REDACTED]/g;
    s/\b((?:api[_-]?key|token|secret|password|passwd|pass))\s*=\s*\S+/$1=[REDACTED]/gi;
  '
}
