package v1

import "strings"

// sanitizeValidationError returns a user-friendly message for validation/binding errors.
// Never expose raw gin/go validation errors to clients (security + UX).
func sanitizeValidationError(err error) string {
	if err == nil {
		return ""
	}
	msg := err.Error()
	if strings.Contains(msg, "validation") ||
		strings.Contains(msg, "Field validation") ||
		strings.Contains(msg, "cannot unmarshal") ||
		strings.Contains(msg, "bind") ||
		strings.Contains(msg, "Key:") {
		return "Invalid request"
	}
	if len(msg) < 100 && !strings.Contains(msg, "Error:") {
		return msg
	}
	return "Invalid request"
}
