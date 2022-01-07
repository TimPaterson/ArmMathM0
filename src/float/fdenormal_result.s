
/*
 * fdenormResult.s
 *
 * Created: 8/8/2021 2:48:57 PM
 *  Author: Tim
 */ 

 .syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"

	.global	__fdenormal_result

//*********************************************************************
// Denormalize a tiny result
//
// Entry:
//	r0 = result, left justified (with trailing sticky bits)
//	r2 = biased result exponent - 1 (negative)
//	r3 = sticky bits
// Exit:
//	r0 = final result w/exponent, right justified
//	r1 destroyed
//*********************************************************************

	.func	__fdenormal_result

	.thumb_func
__fdenormal_result:
	// There are 7 sticky bits in r0 below the rounding bit.
	// Keep these along with the bits we shift out denormalizing.
	adds	r2, #32 - 7
	movs	r1, r0
	lsls	r1, r2
	// We'll shift right all the way to normal alignment,
	// shifting the rounding bit into the CY
	subs	r2, #32 + 1
	negs	r2, r2
	lsrs	r0, r2
	bcc	Exit		// CY not set means no rounding bit
	// Round, checking for round-even if exactly halfway
	orrs	r3, r1		// test sticky bits
	bne	RoundUp		// sticky set, round up
	lsls	r1, r0, #31	// test LSB for round even
	bpl	Exit
RoundUp:
	adds	r0, #1		// round up
	// If this round up caused a carry into the bottom of the
	// exponent (leaving the mantissa zero), then we're all 
	// set up with the smallest normalized number.
Exit:
	bx	lr

	.endfunc
