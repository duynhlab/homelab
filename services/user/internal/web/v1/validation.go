package v1

import "strings"

// sanitizeValidationError returns a user-friendly message for validation/binding errors.
// Never expose raw gin/go validation errors to clients (security + UX).
func sanitizeValidationError(err error) string {
	if err == nil {
		return ""
	}
	msg := err.Error()
	// Raw validation errors expose internal structure - return generic message
	if strings.Contains(msg, "validation") ||
		strings.Contains(msg, "Field validation") ||
		strings.Contains(msg, "cannot unmarshal") ||
		strings.Contains(msg, "bind") ||
		strings.Contains(msg, "Key:") {
		return "Invalid request"
	}
	// Short, safe messages (e.g. "invalid email") can pass through
	if len(msg) < 100 && !strings.Contains(msg, "Error:") {
		return msg
	}
	return "Invalid request"
}
