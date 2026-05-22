//****************************************************************************
// asinf.s
//
// Created 9/2/2024 4:09:38 PM by Tim Paterson
//
//****************************************************************************

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"
.include "trigf.inc"


	.global __AsinReentry

//*********************************************************************
// 32-bit floating-point arc sine
//
// Entry:
//	r0 = sine of angle
// Exit:
//	r0 = angle
//
// The calculation will use CORDIC rotation of the input vector to
// accumulate the angle required to bring y = sine of input.
//
// The formula for a single rotation at iteration i is:
//
// x' = x + d * y * 2^-i
// y' = y - d * x * 2^-i
//
// where d is the direction of rotation, +1 or -1.
//
// A single rotation increases the vector length by a factor of
// sqrt(1 + 2^-2i), which would require a lookup table and multiply.
// Instead we do two iterations at once, so the vector length
// increases by a factor of 1 + 2^-2i, achieved with shift/add.
//
// The double rotation becomes:
//
// x'' = x' + d * y' * 2^-i
// x'' = x + d * y * 2^-i + d * (y - d * x * 2^-i) * 2^-i
// x'' = x + d * y * 2^-i + d * y * 2^-i - x * 2^-i * 2^-i
// x'' = x - x * 2^-2i + d * y * 2^(1-i)
//
// y'' = y' - d * x' * 2^-i
// y'' = y - d * x * 2^-i - d * (x + d * y * 2^-i) * 2^-i
// y'' = y - d * x * 2^-i - d * x * 2^-i - y * 2^-i * 2^-i
// y'' = y - y * 2^-2i - d * x * 2^(1-i)
//
// The "p" notation used throughout is the position of the binary point
// (p16 means there are 16 bits to the right).
//*********************************************************************


.set	ASIN_TABLE_ENTRIES,	14
.set	SMALL_ASIN_TABLE_ENTRIES, SMALL_ATAN_TABLE_ENTRIES
.set	SIN_X_EQUALS_X_EXP,	-11
.set	SMALL_ANGLE_SHIFT,	6
.set	SMALL_TABLE_EXP,	-5
.set	LARGE_INPUT_MANTISSA,	237	// 0.925 * 2^8
// 0.00055893 is the largest input that equals result to 0.5 ULP.
// The CORDIC loop returns output == input up to 0.000647
//.set	TINY_INPUT_MANISSA,	146	// 0.0005589 * 2^18
.set	TINY_INPUT_MANISSA,	169	// 0.000647  * 2^18

	.func	asinf

SmallInput:
	// r0 = original input
	// r1 = mantissa, MSB set in bit 31
	// r2 = exponent + 1 (no bias)
	// r3 = mantissa p30
	// r5 = -exponent - 1 (no bias)
	// r6 = __sineAtanTable
	cmp	r5, #-SIN_X_EQUALS_X_EXP - 1
	blt	UseSmalltable
	bgt	ReturnOp
	lsrs	r4, r3, #23
	cmp	r4, #TINY_INPUT_MANISSA
	blt	ReturnOp
UseSmalltable:
	adds	r6, #SMALL_ATAN_TABLE_OFFSET - 4 // offset from __sineAtanTable instead of __fullAtanTable
	subs	r2, r5, #SMALL_ATAN_TABLE_SHIFT
	lsls	r2, #2
	adds	r7, r6, r2		// skip entries in table
	adds	r6, #4 * SMALL_ASIN_TABLE_ENTRIES // end of table + 1
	// r3 = t * 2^s, target sine
	// r5 = s, scale factor
	// r6 = ptr to end of angle table
	// r7 = ptr to table of angles [atan(2^-i)]
	b	InitRotation

TooBig:
	cmp	r3, #EXP_SPECIAL32 - EXP_BIAS32 + 1
	bne	ReturnNan
	// If argument is NAN, return it.
	// If it's infinity, make a new NAN.
	lsls	r2, r0, #EXP_BITS32 + 1	// mantissa == 0?
	bne	ReturnOp	// input is NAN, return it
ReturnNan:
	ldr	r0, =#NAN32
ReturnOp:
	// r0 = original input
	// r1 = mantissa, MSB set in bit 31
	// r2 = exponent + 1 (no bias)
	//
	// In case  we entered at __AsinReentry, set up return values
	adds	r2, #EXP_BIAS32 - 2	// biased exponent
	// r0 = original input
	// r1 = mantissa, MSB set
	// r2 = biased exponent
	pop	{r3, r4-r7, pc}

HugeInput:
	// r0 = original input
	// r1 = mantissa, MSB set in bit 31
	// r2 = exponent + 1 (no bias)
	// r3 = sign
	cmp	r2, #1		// exp = 1 => 1 <= x < 2
	bne	TooBig
	// 1 <= x < 2. If x == 1 return +/-pi/2, otherwise NAN.
	lsls	r1, #1		// ignore implied bit position
	bne	ReturnNan
	// Input is exactly 1
	LOAD_FLOAT	r0, 0, 0, PI_MANTISSA_FLOAT	// 0 sign, 0 exp. = PI/2
	lsls	r3, #31		// sign to MSB
	orrs	r0, r3
	pop	{r2, r4-r7, pc}

LargeInput:
	// r1 = mantissa, MSB set in bit 31
	//
	// For values close to 1, use formula:
	// arcsin(x) = arccos(sqrt(1 - x^2))
	bl	__fsqrt1minusXsquared
	bl	__AcosReentry
	b	CheckSign

__AsinReentry:
	// r1 = mantissa p32
	// r2 = exponent + 1 (no bias)
	movs	r3, #0		// positive sign
	push	{r3, r4-r7, lr}
	// Combine in case its small. This is used when it's small
	// enough that sin(x) = x within float precision. However,
	// sin(x) > x, so we round up at the end.
	movs	r3, r2
	adds	r3, #EXP_BIAS32 - 2
	lsls	r3, #MANT_BITS32
	lsrs	r0, r1, #EXP_BITS32
	adds	r0, r3
	adds	r0, #1		// take ceiling
	b	NormInput


ENTRY_POINT	__asinfM0, asinf
	asrs	r3, r0, #31		// save input sign
	push	{r3, r4-r7, lr}
	lsls	r2, r0, #1		// clear input sign
	lsrs	r2, #MANT_BITS32 + 1	// isolate exponent
	lsls	r4, r0, #EXP_BITS32	// isolate mantissa
	MOV_IMM	r1, 0x80000000		// implied bit position
	orrs	r1, r4
	subs	r2, #EXP_BIAS32 - 1
	// r0 = original input
	// r1 = mantissa, MSB set in bit 31
	// r3 = sign
	// r2 = exponent + 1 (no bias)
	blt	NormInput	// abs(arg) < 0.5
	bne	HugeInput	// abs(arg) >= 1
	// 0.5 <= x < 1
	lsrs	r4, r1, #24		// look at top 8 bits of arg
	cmp	r4, #LARGE_INPUT_MANTISSA
	bhs	LargeInput
NormInput:
	// r0 = original input
	// r1 = mantissa, MSB set in bit 31
	// r2 = exponent + 1 (no bias)
	negs	r5, r2		// -exponent - 1
	lsrs	r3, r1, #1	// p31
	ldr	r6, =#__sineAtanTable
	cmp	r5, #-SMALL_TABLE_EXP
	bgt	SmallInput
	lsls	r0, r5, #2
	adds	r7, r6, r0		// skip entries in table
	adds	r6, #4 * ASIN_TABLE_ENTRIES	// end of table + 1
InitRotation:
	// r3 = t * 2^s, target sine
	// r5 = s, scale factor
	// r6 = ptr to end of angle table
	// r7 = ptr to table of angles [atan(2^-i)]
	mov	r12, r6
	movs	r0, #0		// y = 0
	MOV_IMM	r1, 0x80000000	// x = 1 p31
	movs	r2, #0		// iteration - s - 1
	movs	r4, #0		// angle = 0
	// Let's do some CORDIC vector rotations!
	// r0 = y * 2^s
	// r1 = x p31
	// r2 = i-s-1 (shift count)
	// r3 = t * 2^s, target sine
	// r4 = z, angle p31
	// r5 = s, scale factor
	// r7 = ptr to table of angles [atan(2^-i)]
	// r12 = ptr to end of angle table
	//
	// y and t are scaled (shifted left) by scale factor s in r5.

RotLoop:
	mov	lr, r7
	lsrs	r6, r1, #2	// x*2^-2
	lsrs	r6, r2		// x*2^(-2+s+1-i) = x*2^(s-i-1)

	lsrs	r7, r0, #2	// y*2^(s-2) (note r0 = y*2^s)
	lsrs	r7, r5		// y*2^(s-2-s) = y*2^-2
	lsrs	r7, r5		// y*2^(-2-s)
	lsrs	r7, r2		// y*2^(-2-s+s+1-i) = y*2^(-i-1)
	cmp	r3, r0
	bhs	AddAngle
	// Subtract angle
	subs	r6, r0, r6	// y*2^s - x*2^(s-i-1) = 2^s*(y - x*2^(-i-1))
	lsrs	r6, r5		// y - x*2^(-i-1)
	adds	r7, r1		// x + y*2^(-i-1)
	lsrs	r7, r2		// x*2^(s+1-i) + y*2^(-i-1+s+1-i) = x*2^(s+1-i) + y*2^(s-2i)
	subs	r0, r7		// y' = y*2^s - x*2^(s+1-i) - y*2^(s-2i) = 2^s*(y - x*2^(1-i) - y*2^(-2i))

	lsrs	r6, r2		// y*2^(s+1-i) - x*2^(-i-1+s+1-i) = 2^s*(y*2^(1-i) - x*2^(-2i))
	lsrs	r6, r5		// y*2^(1-i) - x*2^(-2i)
	adds	r1, r6		// x' = x + y*2^(1-i) - x*2^-2i
	// accumulate angle
	mov	r7, lr
	ldmia	r7!, {r6}	// atan(2^-i) p32 = 2 * atan(2^-i) p31
	subs	r4, r6		// new angle
	b	FinishRotation

AddAngle:
	subs	r7, r1, r7	// x - y*2^(-i-1)
	adds	r6, r0		// y*2^s + x*2^(s-i-1) = 2^s*(y + x*2^(-i-1))
	lsrs	r6, r5		// y + x*2^(-i-1)
	lsrs	r7, r2		// x*2^(s+1-i) - y*2^(s+1-i-i-1) = x*2^(s+1-i) - y*2^(s-2i)
	adds	r0, r7		// y' = y*2^s + x*2^(s+1-i) - y*2^(s-2i) = 2^s*(y + x*2^(1-i) - y*2^(-2i))
	lsrs	r6, r2		// y*2(s+1-i) + x*2^(s+1-i-i-1) = 2^s*(y*2(1-i) + x*2^(-2i))
	lsrs	r6, r5		// y*2^(1-i) + x*2^(-2i)
	subs	r1, r6		// x' = x - y*2^(1-i) - x*2^(-2i)
	// accumulate angle
	mov	r7, lr
	ldmia	r7!, {r6}	// atan(2^-i) p32 = 2 * atan(2^-i) p31
	adds	r4, r6		// new angle
FinishRotation:
	// adjust vector length
	lsrs	r6, r3, #2	// t*2^(s-2)
	lsrs	r6, r5		// t*2^(-2)
	lsrs	r6, r5		// t*2^(-s-2)
	lsrs	r6, r2		// t*2^(s+1-i-s-2) = t*2^(-i-1)
	lsrs	r6, r2		// t*2^(s+1-i-i-1) = t*2^(s-2i)
	adcs	r3, r6		// t' = 2^s*(t + t*2^(-2i)), with rounding
	adds	r2, #1		// next iteration
	cmp	r7, r12
	blo	RotLoop
	movs	r7, #EXP_BIAS32 - 1	// exponent
	cmp	r5, #-SMALL_TABLE_EXP
	ble	1f
	subs	r7, #SMALL_ATAN_TABLE_SHIFT
	subs	r5, #SMALL_ATAN_TABLE_SHIFT
1:
	// r0 = y * 2^s
	// r1 = x p31
	// r3 = t * 2^s, target sine
	// r4 = z, angle p31
	// r5 = s, scale factor
	// r7 = exponent
	//
	// We have used CORDIC to get us an angle (z) whose sine (y) is
	// very close to our target. The remaining error angle d is so
	// small that (in 24-bit precision) cos(d) = 1 and sin(d) = d.
	// This allows us to simplify the rotation formula:
	// x' = x*cos(d) - y*sin(d) => x' = x - y*d
	// y' = x*sin(d) + y*cos(d) => y' = x*d + y
	// We want y' = t, => x*d + y = t
	// Solving for d: d = (t - y) / x
	// So we can compute that last rotation in one shot.

	subs	r0, r3, r0	// t - y p31
	bl	__fixed_dividef
	asrs	r0, r5		// remove scale
	adds	r1, r4, r0	// z += q p31
	bmi	Combine
NormLoop:
	// r1 = z, angle p31
	// r7 = exponent
	subs	r7, #1
	adds	r1, r1
	bpl	NormLoop	// until we shift off MSB
Combine:
	// r1 = mantissa, MSB set
	// r7 = biased exponent
	movs	r2, r7			// return exponent
	lsls	r3, r2, #MANT_BITS32	// position exponent
	lsrs	r0, r1, #EXP_BITS32	// position mantissa
	adcs	r0, r3		// combine exponent and rounding bit
CheckSign:
	pop	{r3}
	lsls	r3, #31		// move LSB to sign
	orrs	r0, r3
	pop	{r4-r7, pc}

	.endfunc
