package http

import (
	"context"
	"fmt"
	"os"
	"strings"

	authapp "nidaw-backend/internal/modules/auth/application"
	notifs "nidaw-backend/internal/shared/integrations/notifications"
)

// smsOTPSender adapts the shared multi-provider notification service to the
// narrow authapp.SMSSender port. Kept in the interfaces layer so the
// application package stays free of infrastructure imports.
type smsOTPSender struct {
	svc        *notifs.MultiProviderNotificationService
	fromNumber string
	template   string // optional SMS_OTP_TEMPLATE key; empty => inline message
}

// NewOTPSMSSender exposes the adapter for server wiring (main.go).
func NewOTPSMSSender(svc *notifs.MultiProviderNotificationService) authapp.SMSSender {
	if svc == nil {
		return nil
	}
	return &smsOTPSender{
		svc:        svc,
		fromNumber: os.Getenv("TWILIO_FROM_NUMBER"),
		template:   os.Getenv("SMS_OTP_TEMPLATE"),
	}
}

func (s *smsOTPSender) SendOTP(ctx context.Context, to, code string) error {
	req := &notifs.SMSRequest{
		To:   to,
		From: s.fromNumber,
	}
	if s.template != "" {
		req.Template = s.template
		req.Vars = map[string]string{"code": code}
	} else {
		req.Message = fmt.Sprintf(
			"%s is your NIDAW verification code. It expires in a few minutes. Never share this code with anyone.",
			strings.TrimSpace(code),
		)
	}
	return s.svc.SendSMS(ctx, req)
}
