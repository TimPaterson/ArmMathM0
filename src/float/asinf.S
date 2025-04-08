//****************************************************************************
// asinf.s
//
// Created 9/2/2024 4:09:38 PM by Tim
//
//****************************************************************************

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"
.include "trigf.inc"


// 32-bit floating-point arc sine
//
// Entry:
//	r0 = sine of angle
// Exit:
//	r0 = angle
//
// The calculation will use CORDIC rotation of the input vector to
// accumulate the angle required to bring y = 0. This is done only
// in the first octant, so argument reduction makes y <= x, x > 0,
// y > 0.
//
// The calculations are semi-fixed point. y is kept normalized so
// as not to lose precision, and shifted during each rotation to line
// up with x. If x >> y, the result will be small and a different
// table of angles [atan(2^-i)] with higher precision is used.
//
// Rotations are used until the angle being rotated by is so small that
// tan(x) = x (for 24-bit precision), so atan(y/x) = y/x. Then we do
// one last rotation by y/x.
//
// The "p" notation used throughout is the position of the binary point
// (p16 means there are 16 bits to the right).


	.func	asinf

SpecialExp:
	// If argument is NAN, return it.
	// If it's infinity, make a new NAN and return it for both.
	lsls	r2, r0, #(EXP_BITS32 + 1)	// mantissa == 0?
	bne	ReturnOp	// input is NAN, return it
ReturnNan:
	ldr	r0, =#NAN32
ReturnOp:
	pop	{r4-r7, pc}


ENTRY_POINT	__asinfM0, asinftim
	push	{r4-r7, lr}
	lsls	r1, r0, #1		// clear input sign
	lsrs	r1, #MANT_BITS32 + 1	// isolate exponent
	cmp	r1, #EXP_SPECIAL32
	beq	SpecialExp
	asrs	r7, r0, #31		// save input sign
	movs	r3, #1
	lsls	r3, #MANT_BITS32	// implied bit position
	orrs	r3, r0
	lsls	r3, #EXP_BITS32		// isolate mantissa
	subs	r1, EXP_BIAS32
	bge	ReturnNan		// oops, fails on +/-1
	negs	r1, r1
	// UNDONE: check for small numbers
	lsrs	r3, r1
	movs	r0, #0			// y = 0
	MOV_IMM	r1, 0x80000000		// x = 1
	movs	r2, #0			// angle = 0
	movs	r5, #1			// shift count
	ldr	r4, =#__sineAtanTable
	mov	r12, r7
	// Let's do some CORDIC vector rotations!
	// r0 = y p31
	// r1 = x p31
	// r2 = angle p31
	// r3 = target sine p31
	// r4 = ptr to table of angles [atan(2^-i)]
	// r5 = iteration i (and shift count)
	// r12 = octant info
RotLoop:
	movs	r7, r0
	lsrs	r7, r5		// y * 2^-i
	movs	r6, r1
	lsrs	r6, r5		// x * 2^-i
	cmp	r3, r0
	bhs	FlipSign
	// round 1
	adds	r1, r7		// x += y * 2^-i
	subs	r0, r6		// y -= x * 2^-i
	// round 2
	movs	r7, r0
	lsrs	r7, r5		// y * 2^-i
	movs	r6, r1
	lsrs	r6, r5		// x * 2^-i
	adds	r1, r7		// x += y * 2^-i
	subs	r0, r6		// y -= x * 2^-i
	// accumulate angle
	ldmia	r4!, {r6}	// next atan()
	subs	r2, r6		// new angle
	b	AdjustSine

FlipSign:
	subs	r1, r7		// x -= y * 2^-i
	adds	r0, r6		// y += x * 2^-i
	// round 2
	movs	r7, r0
	lsrs	r7, r5		// y * 2^-i
	movs	r6, r1
	lsrs	r6, r5		// x * 2^-i
	subs	r1, r7		// x -= y * 2^-i
	adds	r0, r6		// y += x * 2^-i
	// accumulate angle
	ldmia	r4!, {r6}	// next atan()
	adds	r2, r6		// new angle
AdjustSine:
	movs	r6, r3
	lsrs	r6, r5
	lsrs	r6, r5
	adds	r3, r6		// sine += sine >> (2 * shift)
	adds	r5, #1		// shift count
	cmp	r5, #SINE_ATAN_TABLE_ENTRIES
	bls	RotLoop
	movs	r1, #EXP_BIAS32 + 1	// exponent
NormLoop:
	subs	r1, #1
	adds	r2, r2
	bcc	NormLoop	// until we shift off MSB
	// combine
	lsls	r1, #MANT_BITS32	// position exponent
	lsrs	r0, r2, #EXP_BITS32 + 1	// position mantissa
	adcs	r0, r1		// combine exponent and rounding bit
	mov	r3, r12
	lsls	r3, #31		// move LSB to sign
	orrs	r0, r3
	pop	{r4-r7, pc}

	.endfunc
