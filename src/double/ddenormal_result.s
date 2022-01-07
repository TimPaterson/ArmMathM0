
/*
 * ddenormResult.s
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

	.global	__ddenormal_result

//*********************************************************************
// Denormalize a tiny result
//
// Entry:
//	r1:r0 = result
//	r2 = biased result exponent - 1 (negative)
//	r4 = sticky bits
// Exit:
//	r1:r0 = final result w/exponent
//*********************************************************************

	.func	__ddenormal_result

	.thumb_func
__ddenormal_result:
	negs	r3, r2
	adds	r2, #32
	bmi	BigShift
	movs	r5, r1
	movs	r6, r0
	lsrs	r1, r3
	lsls	r5, r2
	lsrs	r0, r3		// CY is rounding bit
	add	r0, r5		// CY not affected
RoundTest:
	bcc	Exit		// no rounding, all done
	lsls	r6, r2		// rounding and sticky bits
	lsls	r6, #1		// drop rounding bit
	orrs	r4, r6		// any sticky bits?
	bne	RoundUp
	lsls	r4, r0, #31	// test LSB for round even
	bpl	Exit
RoundUp:
	adds	r0, #1		// round up
	bcc	Exit
	adds	r1, #1
	// If this round up caused a carry into the bottom of the
	// exponent (leaving the mantissa zero), then we're all 
	// set up with the smallest normalized number.
Exit:
	bx	lr

BigShift:
	orrs	r4, r0
	movs	r0, r1
	movs	r1, #0
	adds	r2, #32
	bmi	RetZero
	subs	r3, #32
	movs	r6, r0
	lsrs	r0, r3		// CY is rounding bit
	b	RoundTest

RetZero:
	movs	r0, r1		// both zero
	bx	lr

	.endfunc
