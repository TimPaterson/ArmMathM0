//****************************************************************************
// acosf.s
//
// Created 4/21/2026 by Tim Paterson
//
//****************************************************************************

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"
.include "trigf.inc"


	.global __AcosReentry

//*********************************************************************
// 32-bit floating-point arc cosine
//
// Entry:
//	r0 = cosine of angle
// Exit:
//	r0 = angle
//
// The calculation will use CORDIC rotation of the input vector to
// accumulate the angle required to bring x = cosine of input.
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
// x'' = x - x * 2^-2i + d * y * 2^(-i+1)
//
// y'' = y' - d * x' * 2^-i
// y'' = y - d * x * 2^-i - d * (x + d * y * 2^-i) * 2^-i
// y'' = y - d * x * 2^-i - d * x * 2^-i - y * 2^-i * 2^-i
// y'' = y - y * 2^-2i - d * x * 2^(-i+1)
//
// The "p" notation used throughout is the position of the binary point
// (p16 means there are 16 bits to the right).
//*********************************************************************


.set	ACOS_X_EQUALS_PI_OVER_2_MINUS_X_EXP,	-9
.set	ACOS_ATAN_TABLE_ENTRIES,		14
.set	LARGE_INPUT_MANTISSA,			222	// 0.87 * 2^8

	.func	acosf

SmallInput:
	// r1 = mantissa, MSB set in bit 31
	// r2 = exponent + 1 (no bias)
	// r3 = sign
	// for small input, acos(x) = pi/2 - x
	MOV_IMM	r0, PI_MANTISSA
	lsrs	r1, r2		// align (to zero if shift count is large)
	lsrs	r1, #1
	// twos-complement of arg if signed
	eors	r1, r3
	subs	r1, r3
	// pi/2 - x
	subs	r0, r1		
	// combine
	MOV_IMM	r2, (EXP_BIAS32 - 1) << MANT_BITS32
	lsrs	r0, #EXP_BITS32	// position mantissa
	adcs	r0, r2		// combine exponent and rounding bit
	pop	{r3-r7, pc}

TooBig:
	// r0 = original input
	// r2 = exponent + 1 (no bias)
	cmp	r2, #EXP_SPECIAL32 - EXP_BIAS32 + 1
	bne	ReturnNan
	// If argument is NAN, return it.
	// If it's infinity, make a new NAN.
	lsls	r3, r0, #EXP_BITS32 + 1	// mantissa == 0?
	bne	ReturnOp	// input is NAN, return it
ReturnNan:
	MOV_IMM	r0, NAN32
ReturnOp:
	pop	{r3-r7, pc}

HugeInput:
	// r0 = original input
	// r1 = mantissa, MSB set in bit 31
	// r2 = exponent + 1 (no bias)
	// r3 = sign
	cmp	r2, #1		// exp = 1 => 1 <= x < 2
	bne	TooBig
	// 1 <= x < 2. If x == 1 return 0 or pi, otherwise NAN.
	lsls	r0, r1, #1	// ignore implied bit position
	bne	ReturnNan
	// Input is exactly 1. Return 0 for +1, pi for -1
	cmp	r3, #0
	beq	ReturnOp	// return 0
	LOAD_FLOAT r0, 0, 1, PI_MANTISSA_FLOAT	// 0 sign, 1 exp. = pi
	pop	{r3-r7, pc}

LargeInput:
	// For values close to 1, use formula:
	// arccos(x) = arcsin(sqrt(1 - x^2))
	bl	__fsqrt1minusXsquared
	bl	__AsinReentry
	// r0 = combined IEEE return value
	// r1 = mantissa, p31 when exponent = 0
	// r2 = biased exponent
	pop	{r3}
	cmp	r3, #0
	beq	LargeExit
	// subtract from pi
	MOV_IMM	r0, PI_MANTISSA	// p30 for pi
	movs	r3, #EXP_BIAS32	// pi exponent of 1 - 1
	subs	r2, r3, r2	// -exponent
	lsrs	r1, r2		// align
	subs	r0, r1
	lsls	r3, #MANT_BITS32// position exponent
	lsrs	r0, #EXP_BITS32	// position mantissa
	adcs	r0, r3		// combine exponent and rounding bit
LargeExit:
	pop	{r4-r7, pc}

__AcosReentry:
	// r1 = mantissa p32
	// r2 = exponent (no bias)
	movs	r3, #0		// positive sign
	push	{r3-r7, lr}
	b	NormInput


ENTRY_POINT	__acosfM0, acosf
	asrs	r3, r0, #31		// save input sign
	push	{r3-r7, lr}
	lsls	r2, r0, #1		// clear input sign
	lsrs	r2, #MANT_BITS32 + 1	// isolate exponent
	lsls	r4, r0, #EXP_BITS32	// isolate mantissa
	MOV_IMM	r1, 0x80000000		// implied bit position
	orrs	r1, r4
	subs	r2, EXP_BIAS32 - 1
	// r0 = original input
	// r1 = mantissa, MSB set in bit 31
	// r2 = exponent + 1 (no bias)
	// r3 = sign
	blt	NormInput		// abs(arg) < 0.5
	bne	HugeInput		// abs(arg) >= 1
	// 0.5 <= x < 1
	lsrs	r4, r1, #24		// look at top 8 bits of arg
	cmp	r4, #LARGE_INPUT_MANTISSA
	bhi	LargeInput
NormInput:
	// r1 = mantissa, MSB set in bit 31
	// r2 = exponent + 1 (no bias)
	// r3 = sign
	negs	r2, r2		// -exponent - 1
	cmp	r2, #-ACOS_X_EQUALS_PI_OVER_2_MINUS_X_EXP - 1
	bgt	SmallInput
	lsrs	r3, r1, #2	// p30
	lsrs	r3, r2
	movs	r1, #0		// y = 0
	MOV_IMM	r0, 0x40000000	// x = 1 p30
	movs	r4, #0		// angle = 0
	movs	r5, #0		// shift count
	ldr	r7, =#__sineAtanTable
	// Let's do some CORDIC vector rotations!
	// r0 = x p30
	// r1 = y p30
	// r3 = t, target sine p30
	// r4 = z, angle p31
	// r5 = iteration i - 1 (shift count)
	// r7 = ptr to table of angles [atan(2^-i)]
RotLoop:
	mov	lr, r7
	lsrs	r6, r1, #2	// y*2^-2
	lsrs	r6, r5		// y*2^(1-i-2) = y*2^(-i-1)
	asrs	r7, r0, #2	// x*2^-2
	asrs	r7, r5		// x*2^(1-i-2) = x*2^(-i-1)
	cmp	r3, r0
	blt	AddAngle
	// Subtract angle
	subs	r7, r1, r7	// y - x*2^(-i-1)
	adds	r6, r0		// x + y*2^(-i-1)
	lsrs	r7, r5		// y*2^(1-i) - x*2^(1-i-i-1) = y*2^(1-i) - x*2^(-2i)
	adds	r0, r7		// x + y*2^(1-i) - x*2^(-2i)
	asrs	r6, r5		// x*2^(1-i) + y*2^(1-i-i-1) = x*2^(1-i) + y*2^(-2i)
	subs	r1, r6		// y - x*2^(1-i) - y*2^(-2i)
	// accumulate angle
	mov	r7, lr
	ldmia	r7!, {r6}	// atan(2^-i) p32 = 2 * atan(2^-i) p31
	subs	r4, r6		// new angle
	b	FinishRotation

AddAngle:
	subs	r6, r0, r6	// x - y*2^(-i-1)
	adds	r7, r1		// y + x*2^(-i-1)
	asrs	r6, r5		// x*2^(1-i) - y*2^(1-i-i-1) = x*2^(1-i) - y*2^(-2i)
	adds	r1, r6		// y + x*2^(1-i) - y*2^(-2i)
	lsrs	r7, r5		// y*2^(1-i) + x*2^(1-i-i-1) = y*2^(1-i) + x*2^(-2i)
	subs	r0, r7		// x = y*2^(1-i) - x*2^(-2i)
	// accumulate angle
	mov	r7, lr
	ldmia	r7!, {r6}	// atan(2^-i) p32 = 2 * atan(2^-i) p31
	adds	r4, r6		// new angle
FinishRotation:
	// adjust vector length
	lsrs	r6, r3, #2	// t*2^(-2)
	lsrs	r6, r5		// t*2^(1-i-2) = t*2^(-i-1)
	lsrs	r6, r5		// t*2^(1-i-i-1) = t*2^(-2i)
	adcs	r3, r6		// t += t*2^(-2i), with rounding

	adds	r5, #1		// next iteration
	cmp	r5, #ACOS_ATAN_TABLE_ENTRIES
	blo	RotLoop

	// r0 = x p30
	// r1 = y p30
	// r3 = t, target sine p30
	// r4 = z, angle p31
	// r7 = exponent
	//
	// We have used CORDIC to get us an angle (z) whose cosine (x) is
	// very close to our target. The remaining error angle d is so
	// small that (in 24-bit precision) cos(d) = 1 and sin(d) = d.
	// This allows us to simplify the rotation formula:
	// x' = x*cos(d) - y*sin(d) => x' = x - y*d
	// y' = x*sin(d) + y*cos(d) => y' = x*d + y
	// We want x' = t, => x - y*d = t
	// Solving for d: d = (x - t) / y
	// So we can compute that last rotation in one shot.

	subs	r0, r3	// x - t p30
	bl	__fixed_dividef
	adds	r2, r4, r0	// z += q p31
	// subtract from pi if negative argument
	pop	{r3}
	movs	r1, #EXP_BIAS32 + 1	// exponent
	cmp	r3, #0
	beq	NormLoop
	MOV_IMM	r0, PI_MANTISSA	// pi p30
	lsrs	r2,  #1		// convert to p30
	subs	r2, r0, r2
	movs	r1, #EXP_BIAS32 + 2
NormLoop:
	subs	r1, #1
	adds	r2, r2
	bcc	NormLoop
	lsls	r1, #MANT_BITS32	// position exponent
	lsrs	r0, r2, #EXP_BITS32 + 1	// position mantissa
	adcs	r0, r1		// combine exponent and rounding bit
	pop	{r4-r7, pc}

	.endfunc
