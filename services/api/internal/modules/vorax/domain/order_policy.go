// Package domain contains Vorax order rules independent of transport and persistence.
package domain

import (
	"errors"
	"math"
)

var (
	ErrInvalidPrice       = errors.New("menu price must be non-negative and finite")
	ErrInvalidQuantity    = errors.New("quantity must be between 1 and 100")
	ErrInvalidDeliveryFee = errors.New("delivery fee must be non-negative and finite")
	ErrBelowMinimum       = errors.New("subtotal is below the restaurant minimum")
	ErrCurrencyMismatch   = errors.New("menu items use incompatible currencies")
)

type PricedLine struct {
	UnitPrice float64
	Quantity  int
	Currency  string
}

// CalculateTotals derives order totals from server-loaded menu prices only.
func CalculateTotals(lines []PricedLine, deliveryFee, minimum float64) (subtotal, total float64, currency string, err error) {
	if !finiteNonNegative(deliveryFee) || !finiteNonNegative(minimum) {
		return 0, 0, "", ErrInvalidDeliveryFee
	}
	if len(lines) == 0 {
		return 0, 0, "", ErrInvalidQuantity
	}
	for _, line := range lines {
		if line.Quantity < 1 || line.Quantity > 100 {
			return 0, 0, "", ErrInvalidQuantity
		}
		if !finiteNonNegative(line.UnitPrice) {
			return 0, 0, "", ErrInvalidPrice
		}
		if line.Currency == "" {
			return 0, 0, "", ErrCurrencyMismatch
		}
		if currency == "" {
			currency = line.Currency
		} else if currency != line.Currency {
			return 0, 0, "", ErrCurrencyMismatch
		}
		subtotal += line.UnitPrice * float64(line.Quantity)
		if !finiteNonNegative(subtotal) {
			return 0, 0, "", ErrInvalidPrice
		}
	}
	if subtotal < minimum {
		return subtotal, 0, currency, ErrBelowMinimum
	}
	total = subtotal + deliveryFee
	if !finiteNonNegative(total) {
		return 0, 0, "", ErrInvalidPrice
	}
	return subtotal, total, currency, nil
}

func finiteNonNegative(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0) && value >= 0
}
