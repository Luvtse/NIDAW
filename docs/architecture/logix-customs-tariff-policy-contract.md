# Logix customs tariff calculation policy contract

**Status: exemption calculation policy unresolved.**

## Current safety behavior

The Logix customs application service rejects tariff rates that are negative, NaN, or infinite. It also rejects a calculated duty amount that is non-finite or negative before persistence.

The former blanket 50% reduction whenever the tariff source returned any exemption identifier was removed. An identifier list does not define the applicable exemption, eligibility, or reduction amount. If any exemption identifiers are returned, declaration preparation fails closed until an authoritative, auditable exemption-calculation policy is supplied.

This is intentionally conservative and may require tariff-policy integration before shipments with exemptions can proceed. It does not invent a replacement rate or legal interpretation.

## Required before enabling exemption-bearing declarations

- Identify the authoritative tariff/exemption source and the domain owner responsible for its interpretation.
- Define how eligibility is determined for the shipment, HS code, origin, destination, and any supporting documents.
- Return a typed decision with the applicable rate/amount, currency, source/version, and explanation rather than a list of opaque identifiers alone.
- Add boundary and contract tests for full exemptions, partial reductions, ineligible claims, expired rules, missing source data, and source errors.
- Persist sufficient calculation provenance for audit and reconciliation.
- Obtain domain/legal approval for the policy before allowing exempt declarations through this path.
