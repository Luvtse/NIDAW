package domain

import (
	"errors"
	"math"
	"testing"
)

func TestCalculateTotals(t *testing.T) {
	subtotal, total, currency, err := CalculateTotals([]PricedLine{{UnitPrice: 12.5, Quantity: 2, Currency: "ETB"}, {UnitPrice: 5, Quantity: 1, Currency: "ETB"}}, 15, 20)
	if err != nil {
		t.Fatal(err)
	}
	if subtotal != 30 || total != 45 || currency != "ETB" {
		t.Fatalf("got subtotal=%v total=%v currency=%q", subtotal, total, currency)
	}
}

func TestCalculateTotalsRejectsMixedCurrency(t *testing.T) {
	_, _, _, err := CalculateTotals([]PricedLine{{UnitPrice: 10, Quantity: 1, Currency: "ETB"}, {UnitPrice: 1, Quantity: 1, Currency: "USD"}}, 0, 0)
	if !errors.Is(err, ErrCurrencyMismatch) {
		t.Fatalf("got %v", err)
	}
}

func TestCalculateTotalsRejectsInvalidValues(t *testing.T) {
	cases := []struct {
		name     string
		lines    []PricedLine
		fee, min float64
		want     error
	}{
		{"negative price", []PricedLine{{UnitPrice: -1, Quantity: 1, Currency: "ETB"}}, 0, 0, ErrInvalidPrice},
		{"nan price", []PricedLine{{UnitPrice: math.NaN(), Quantity: 1, Currency: "ETB"}}, 0, 0, ErrInvalidPrice},
		{"zero quantity", []PricedLine{{UnitPrice: 1, Quantity: 0, Currency: "ETB"}}, 0, 0, ErrInvalidQuantity},
		{"below minimum", []PricedLine{{UnitPrice: 2, Quantity: 1, Currency: "ETB"}}, 1, 3, ErrBelowMinimum},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, _, _, err := CalculateTotals(tc.lines, tc.fee, tc.min)
			if !errors.Is(err, tc.want) {
				t.Fatalf("got %v, want %v", err, tc.want)
			}
		})
	}
}
