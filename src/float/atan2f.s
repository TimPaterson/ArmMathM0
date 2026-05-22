
/*
 * atan2f.s
 *
 * Created: 7/3/2023 2:42:46 PM
 *  Author: Tim Paterson
 */

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"
.include "trigf.inc"


// 32-bit floating-point arc tangent
//
// Entry:
//	r0 = y-coordinate
//	r1 = x-coordinate
// Exit:
//	r0 = arc tangent of y/x
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


.set	TAN_X_EQUALS_X_EXP,	-12

.set	RECIPROCAL_GUESS_LO,	0xBB	// about 2.92 p6 - see fdiv.s
.set	RECIPROCAL_GUESS_HI,	0xB6	// about 5.69 p5 - see below
.set	ODD_OCTANT_FLAG,	4
.set	SHIFT_START,		1

	SET_FLOAT	PI_OVER_TWO_FLOAT, 0, 0, PI_MANTISSA_FLOAT
	SET_FLOAT	PI_FLOAT, 0, 1, PI_MANTISSA_FLOAT


	.func	__atan2f

SpecialExpY:
	// r0 = |y|
	// r1 = |x|
	// r2 = y biased exponent
	// r3 = sign of x in bit 0
	// r5 = 0x80000000 (sign bit position)
	// r6 = sign of y in bit 0
	//
	// y is special, x unknown. Check for NAN.
	lsls	r5, r0, #EXP_BITS32 + 1
	bne	SetSignY	// return NAN with original sign
	// y is infinity
	lsrs	r7, r1, #MANT_BITS32	// isolate x exponent
	cmp	r7, #EXP_SPECIAL32
	bne	Yaxis
	lsls	r5, r1, #EXP_BITS32 + 1	// is x NAN?
	bne	Xnan
	// both are infinity
ReturnNan:
	MOV_IMM	r0, NAN32
	pop	{r4-r7, pc}

ZeroExpY:
	// r0 = |y|
	// r1 = |x|
	// r2 = y biased exponent
	// r3 = sign of x in bit 0
	// r5 = 0x80000000 (sign bit position)
	// r6 = sign of y in bit 0
	//
	// y exponent is zero, x unknown.

.ifndef	NO_DENORMALS
	lsls	r4, r0, #EXP_BITS32
	beq	Yzero
	// y is denormal, so normalize it

	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r7, r3, r12 preserved
	// r5, r6 trashed
	mov	r12, r6
	bl	__clz_denormal	// Get leading zeros in y
	mov	r6, r12
	negs	r2, r4		// y biased exponent
	adds	r2, #1
	lsls	r0, r4		// normalize y
	// restore r5
	movs	r5, #1
	lsls	r5, #31		// sign position
	b	YNormalized
.endif

Yzero:
	// y is zero, x unknown.
.ifndef	NO_DENORMALS
	cmp	r1, #0
	beq	ReturnNan		// both 0, return NAN
	lsrs	r7, r1, #MANT_BITS32	// isolate x exponent
.else
	lsrs	r7, r1, #MANT_BITS32	// isolate x exponent
	beq	ReturnNan		// both 0, return NAN
.endif
	cmp	r7, #EXP_SPECIAL32
	bne	Xaxis
	lsls	r5, r1, #EXP_BITS32 + 1	// is x NAN?
	beq	Xaxis
Xnan:
	lsls	r3, #31
	orrs	r1, r3
	movs	r0, r1
Exit:
	pop	{r4-r7, pc}

SpecialExpX:
	// r0 = |y|
	// r1 = |x|
	// r2 = y biased exponent
	// r3 = sign of x in bit 0
	// r5 = 0x80000000 (sign bit position)
	// r6 = sign of y in bit 0
	// r7 = x biased exponent
	//
	// x is special and y is not zero or special. Check for infinity.
	lsls	r2, r1, #EXP_BITS32 + 1
	bne	Xnan
Xaxis:
	// x is infinity or y is 0. Return 0 for x > 0, pi * sgn(y) for x < 0
	movs	r0, r3		// get sign of x, set flags
	beq	SetSignY
	ldr	r0, =#PI_FLOAT
SetSignY:
	lsls	r6, #31
	orrs	r0, r6
	pop	{r4-r7, pc}


ZeroExpX:
	// r0 = |y|
	// r1 = |x|
	// r2 = y biased exponent
	// r3 = sign of x in bit 0
	// r5 = 0x80000000 (sign bit position)
	// r6 = sign of y in bit 0
	// r7 = x biased exponent
	//
	// x is zero and y is not zero or special.

.ifndef	NO_DENORMALS
	lsls	r4, r1, #EXP_BITS32
	beq	Yaxis
	// x is denormal, so normalize it

	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r7, r3, r12 preserved
	// r5, r6 trashed
	mov	r12, r6
	bl	__clz_denormal	// Get leading zeros in x
	mov	r6, r12
	negs	r7, r4		// x biased exponent
	adds	r7, #1
	lsls	r1, r4		// normalize x
	MOV_IMM	r5, 0x80000000	// restore r5
	b	XNormalized
.endif

Yaxis:
	// x is zero or y is infinity. Return pi/2 signed as y.
	ldr	r0, =#PI_OVER_TWO_FLOAT
	b	SetSignY


ENTRY_POINT	__atanfM0, atanf
	MOV_IMM	r1, ONE32
	//
	// Fall into __atan2f
	//
ENTRY_POINT	__atan2fM0, atan2f
	push	{r4-r7, lr}
	lsrs	r6, r0, #31	// save y input sign
	lsrs	r3, r1, #31	// save x input sign
	MOV_IMM	r5, 0x80000000	// sign bit, implied bit when normalized
	bics	r0, r5		// clear y sign
	bics	r1, r5		// clear x sign
	lsrs	r2, r0, #MANT_BITS32	// isolate y exponent
	beq	ZeroExpY
	cmp	r2, #EXP_SPECIAL32
	beq	SpecialExpY
YNormalized:
	lsrs	r7, r1, #MANT_BITS32	// isolate x exponent
	beq	ZeroExpX
	cmp	r7, #EXP_SPECIAL32
	beq	SpecialExpX
XNormalized:
	subs	r7, r2		// exponent difference
.ifndef	NO_DENORMALS
	blt	SwapXY
	bgt	YlessThanX
.endif
	cmp	r0, r1
	ble	YlessThanX
SwapXY:
	SWAP	r0, r1
	adds	r6, #ODD_OCTANT_FLAG
	negs	r7, r7
YlessThanX:
	lsls	r3, #1		// x sign to bit 1
	orrs	r3, r6		// combine signs
	mov	r12, r3
	lsls	r0, #EXP_BITS32
	orrs	r0, r5		// normalize y and set implied bit
	lsls	r1, #EXP_BITS32
	orrs	r1, r5		// normalize x and set implied bit
	lsrs	r0, #1		// y p30
	lsrs	r1, #1		// x p30
	cmp	r7, #-TAN_X_EQUALS_X_EXP
	bhi	SmallAtan	// no rotations needed

	// Let's do some CORDIC vector rotations!
	ldr	r2, =#__fullAtanTable
	movs	r6, #ATAN_TABLE_END_OFFSET
	adds	r6, r2
	lsls	r7, #1		// double the shift for y
	beq	SkipFirstRotation
	cmp	r7, #2*SMALL_ATAN_TABLE_START_I
	blt	IndexTable
	adds	r2, #SMALL_ATAN_TABLE_OFFSET - SMALL_ATAN_TABLE_START_I * 4
	adds	r6, #SMALL_ATAN_TABLE_END_OFFSET
IndexTable:
	// Skip over one entry in the table for each count of exp. diffference
	adds	r2, r7
	adds	r2, r7		// skip exp. dif table entries (4 bytes each)
	// Perform first rotation inline
	movs	r3, r0
	lsrs	r3, r7		// account for scaling
	subs	r0, r1		// y -= x * 2^-0
	adds	r1, r3		// x += y * 2^-0
SkipFirstRotation:
	ldmia	r2!, {r4}	// initial atan()
	movs	r5, #SHIFT_START
	mov	lr, r6
	// r0 = y p30
	// r1 = x p30
	// r2 = ptr to table of angles [atan(2^-i)]
	// r5 = iteration i (and shift count)
	// r4 = z p32 (current angle)
	// r7 = scale factor - exp. dif * 2
	// r12 = octant info
	// lr = end of table
RotLoop:
	movs	r3, r0
	asrs	r3, r7		// account for scaling
	asrs	r3, r5		// y * 2^-i
	movs	r6, r1
	lsrs	r6, r5		// x * 2^-i
	adds	r5, #1
	cmp	r0, #0
	blt	TooSmall
	adds	r1, r3		// x += y * 2^-i
	subs	r0, r6		// y -= x * 2^-i
	ldmia	r2!, {r6}	// next atan()
	adds	r4, r6		// new angle
	cmp	r2, lr
	bne	RotLoop
	b	LoopDone

SmallAtan:
	movs	r4, #0		// initialize angle to zero
	b	ComputeYoverX

TooSmall:
	subs	r1, r3		// x -= y * 2^-i
	adds	r0, r6		// y += x * 2^-i
	ldmia	r2!, {r6}	// next atan()
	subs	r4, r6		// new angle
	cmp	r2, lr
	bne	RotLoop
LoopDone:
	lsrs	r7, #1		// restore exponent difference

	// We're close enough so atan(y/x) = y/x.
	//
	// r0 = y p30
	// r1 = x p30
	// r4 = z p32 or p38
	// r7 = exponent difference
	// r12 = octant info
ComputeYoverX:
	mov	r5, r12		// octant info
	bl	__fixed_dividef

	// r0 = y/x p31
	// r4 = z p32 or p38
	// r7 = exponent difference
	// r5 = octant info
	// if exponent difference > SMALL_ATAN_TABLE_START_I, z is p38

	movs	r6, #EXP_BIAS32
	subs	r7, #1
	bgt	TestSmallTable
	negs	r7, r7
	lsls	r0, r7		// align y/x with z
	b	Sum

TestSmallTable:
	subs	r6, r7
	cmp	r7, #SMALL_ATAN_TABLE_START_I - 1
	blt	Align
	subs	r7, #SMALL_ATAN_TABLE_SHIFT
Align:
	lsls	r4, r7		// align y/x with z
Sum:
	adds	r2, r4, r0		// z + y/x, final atan mantissa

	// r2 = z (angle) p32
	// r5 = octant info
	//
	// Octant info:
	// bit 0 = orignal sign of y => copy to result
	// bit 1 = orignal sign of x
	// bit 2 = |y| > |x|
	//
	// bits  y>x  sgn(x)  action
	//--------------------------
	//  00x   n     +     none
	//  01x   n     -     subtract from pi
	//  10x   y     +     subtract from pi/2
	//  11x   y     -     add pi/2
	//
	cmp	r5, #2
	blt	NormLoop
	ldr	r0, =#PI_MANTISSA	// p30 for pi
	lsrs	r3, r5, #2	// isolate octant bit 2
	lsrs	r0, r3		// if 1xx, convert to pi/2
	movs	r7, #EXP_BIAS32 + 2
	subs	r7, r6
	movs	r6, #EXP_BIAS32 + 2
.ifndef	NO_DENORMALS
	// exponent difference can exceed 8 bits
	cmp	r7, #32		// shifting to zero?
	blt	1f
	movs	r2, #0
1:
.endif
	lsrs	r2, r7		// z p30
	cmp	r5, #6
	bge	AddCorrection
	negs	r2, r2		// subtract instead
AddCorrection:
	adds	r2, r0

	// Normalize the z result in r2.
NormLoop:
	subs	r6, #1
	adds	r2, r2
	bcc	NormLoop	// until we shift off MSB

	// r2 = z
	// r6 = exponent of z
	// r5 = octant info
PositionExp:
	lsls	r0, r6, #MANT_BITS32	// position exponent
	beq	RoundChk
	bmi	TinyResult
Pack:
	lsrs	r2, #EXP_BITS32 + 1	// position mantissa
	adcs	r0, r2		// combine exponent, inc. rounding bit
SetSign:
	lsls	r5, #31		// original sign of y
	orrs	r0, r5		// sign of result is sign of y
	pop	{r4-r7, pc}

.ifdef NO_DENORMALS
RoundChk:
	// see if if could round up to a normal number
	movs	r6, 1		//  exponent if round up works
	MOV_IMM	r3, 0x200
	adds	r2, r3
	beq	PositionExp
TinyResult:
.else
RoundChk:
TinyResult:
	// result is tiny
	negs	r6, r6
	cmp	r6, #25		// shifting to zero?
	bhs	ReturnZero
	lsrs	r2, #1		// make room for mantissa MSB, no longer implied
	movs	r1, #1
	lsls	r1, #31
	orrs	r2, r1		// set result MSB
	lsrs	r2, r6		// denormalize
	movs	r0, #0		// zero exponent
	b	Pack

.endif
ReturnZero:
	movs	r0, #0
	b	SetSign

	.endfunc
