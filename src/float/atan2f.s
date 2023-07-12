
/*
 * atan2f.s
 *
 * Created: 7/3/2023 2:42:46 PM
 *  Author: Tim
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
	// r5 = 0x80000000 (sign bit position)
	// r6 = sign of y in bit 0
	// r7 = sign of x in bit 0
	//
	// y is special, x unknown. Check for NAN.
	lsls	r5, r0, #EXP_BITS32 + 1
	bne	SetSignY	// return NAN with original sign
	// y is infinity
	lsrs	r3, r1, #MANT_BITS32	// isolate x exponent
	cmp	r3, #EXP_SPECIAL32
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
	// r5 = 0x80000000 (sign bit position)
	// r6 = sign of y in bit 0
	// r7 = sign of x in bit 0
	//
	// y exponent is zero, x unknown.

.ifndef	NO_DENORMALS
	lsls	r4, r0, #EXP_BITS32
	beq	Yzero
	// y is denormal, so normalize it

	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r3, r7, r12 preserved
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
	lsrs	r3, r1, #MANT_BITS32	// isolate x exponent
.else
	lsrs	r3, r1, #MANT_BITS32	// isolate x exponent
	beq	ReturnNan		// both 0, return NAN
.endif
	cmp	r3, #EXP_SPECIAL32
	bne	Xaxis
	lsls	r5, r1, #EXP_BITS32 + 1	// is x NAN?
	beq	Xaxis
Xnan:
	lsls	r7, #31
	orrs	r1, r7
	movs	r0, r1
Exit:
	pop	{r4-r7, pc}

SpecialExpX:
	// r0 = |y|
	// r1 = |x|
	// r2 = y biased exponent
	// r3 = x biased exponent
	// r5 = 0x80000000 (sign bit position)
	// r6 = sign of y in bit 0
	// r7 = sign of x in bit 0
	//
	// x is special and y is not zero or special. Check for infinity.
	lsls	r2, r1, #EXP_BITS32 + 1
	bne	Xnan
Xaxis:
	// x is infinity or y is 0. Return 0 for x > 0, pi * sgn(y) for x < 0
	movs	r0, r7		// get sign of x, set flags
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
	// r3 = x biased exponent
	// r5 = 0x80000000 (sign bit position)
	// r6 = sign of y in bit 0
	// r7 = sign of x in bit 0
	//
	// x is zero and y is not zero or special.

.ifndef	NO_DENORMALS
	lsls	r4, r1, #EXP_BITS32
	beq	Yaxis
	// x is denormal, so normalize it

	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r3, r7, r12 preserved
	// r5, r6 trashed
	mov	r12, r6
	bl	__clz_denormal	// Get leading zeros in x
	mov	r6, r12
	negs	r3, r4		// x biased exponent
	adds	r3, #1
	lsls	r1, r4		// normalize x
	// restore r5
	movs	r5, #1
	lsls	r5, #31		// sign position
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
	lsrs	r7, r1, #31	// save x input sign
	movs	r5, #1
	lsls	r5, #31		// sign bit, implied bit when normalized
	bics	r0, r5		// clear y sign
	bics	r1, r5		// clear x sign
	lsrs	r2, r0, #MANT_BITS32	// isolate y exponent
	beq	ZeroExpY
	cmp	r2, #EXP_SPECIAL32
	beq	SpecialExpY
YNormalized:
	lsrs	r3, r1, #MANT_BITS32	// isolate x exponent
	beq	ZeroExpX
	cmp	r3, #EXP_SPECIAL32
	beq	SpecialExpX
XNormalized:
	subs	r3, r2		// exponent difference
.ifndef	NO_DENORMALS
	blt	SwapXY
	bgt	YlessThanX
.endif
	cmp	r0, r1
	ble	YlessThanX
SwapXY:
	SWAP	r0, r1
	adds	r6, #ODD_OCTANT_FLAG
	negs	r3, r3
YlessThanX:
	lsls	r7, #1		// x sign to bit 1
	orrs	r7, r6		// combine signs
	mov	r12, r7
	lsls	r0, EXP_BITS32
	orrs	r0, r5		// normalize y and set implied bit
	lsls	r1, EXP_BITS32
	orrs	r1, r5		// normalize x and set implied bit
	lsrs	r0, #1		// y p30
	lsrs	r1, #1		// x p30
	cmp	r3, #-TAN_X_EQUALS_X_EXP
	bhi	SmallAtan	// no rotations needed

	// Let's do some CORDIC vector rotations!
	ldr	r4, =#__fullAtanTable
	movs	r6, #ATAN_TABLE_END_OFFSET
	adds	r6, r4
	lsls	r3, #1		// double the shift for y
	beq	SkipFirstRotation
	cmp	r3, #2*SMALL_ATAN_TABLE_START_I
	blt	IndexTable
	adds	r4, SMALL_ATAN_TABLE_OFFSET - SMALL_ATAN_TABLE_START_I * 4
	adds	r6, SMALL_ATAN_TABLE_END_OFFSET
IndexTable:
	// Skip over one entry in the table for each count of exp. diffference
	adds	r4, r3
	adds	r4, r3		// skip exp. dif table entries (4 bytes each)
	// Perform first rotation inline
	movs	r7, r0
	lsrs	r7, r3		// account for scaling
	subs	r0, r1		// y -= x * 2^-0
	adds	r1, r7		// x += y * 2^-0
SkipFirstRotation:
	ldmia	r4!, {r2}	// initial atan()
	movs	r5, #SHIFT_START
	mov	lr, r6
	// r0 = y p30
	// r1 = x p30
	// r2 = z p32 (current angle)
	// r3 = scale factor - exp. dif * 2
	// r4 = ptr to table of angles [atan(2^-i)]
	// r5 = iteration i (and shift count)
	// r12 = octant info
	// lr = end of table
RotLoop:
	movs	r7, r0
	asrs	r7, r3		// account for scaling
	asrs	r7, r5		// y * 2^-i
	movs	r6, r1
	lsrs	r6, r5		// x * 2^-i
	adds	r5, #1
	cmp	r0, #0
	blt	TooSmall
	adds	r1, r7		// x += y * 2^-i
	subs	r0, r6		// y -= x * 2^-i
	ldmia	r4!, {r6}	// next atan()
	adds	r2, r6		// new angle
	cmp	r4, lr
	bne	RotLoop
	b	LoopDone

SmallAtan:
	movs	r2, #0		// initialize angle to zero
	b	ComputeYoverX

TooSmall:
	subs	r1, r7		// x -= y * 2^-i
	adds	r0, r6		// y += x * 2^-i
	ldmia	r4!, {r6}	// next atan()
	subs	r2, r6		// new angle
	cmp	r4, lr
	bne	RotLoop
LoopDone:
	lsrs	r3, #1		// restore exponent difference

	// We're close enough so atan(y/x) = y/x.
	//
	// Of course, division isn't fun. We'll use Newton-Raphson
	// iteration to calculate the reciprocal of x and multiply that
	// by y for y/x. You can find more details in fdiv.s.
	//
	// The maximum initial vector length occurs when 
	// x = y = (2 - 1 ULP), for a length of sqrt(2^2 + 2^2) = 2.83.
	// Every rotation by atan(2^-i) increases the vector length by
	// 1/cos(2^-i), which is a factor of 1.164 if all rotations are
	// done. This gives a max final vector length of about 3.2935.
	// This means we have to calculate the reciprocal of x over a
	// longer range, or actually two ranges, [1, 2) and [2, 3.3). 
	//
	// We'll use the method used in fdiv.s to make an initial guess
	// for the lower range: guess g = (2.92-x)/2. For the upper range, 
	// we use use g = (K-x)/8, computing K as follows to miminize error:
	//
	// error e = 1 - x*g = 1 - x*(K-x)/8 = 1 - x*K/8 + x^2/8
	// 
	// Derivative to find max: e' = x/4 - K/8 = 0 => x = K/2
	// So e(max) = e(K/2) = 1 - K^2/16 + K^2/32 = 1 - K^2/32
	//
	// Choose K so that -e(max) = e(L), where L = upper limit 3.293:
	//
	// K^2/32 - 1 = 1 - L*K/8 + L^2/8 => K^2/32 + L*K/8 - 2 - L^2/8 = 0
	//
	// One of whose solutions is 5.69214. Round to 8 bits gives 0xB6 p5,
	// which is 5.6875, and max error is 0.0144, more than 6 bits, vs.
	// 3.68 bits for the [1, 2) range.
	//
	// r0 = y p30
	// r1 = x p30
	// r2 = z p32 or p38
	// r3 = exponent difference
	// r12 = octant info
ComputeYoverX:

	lsrs	r5, r1, #13	// 1 <= x < 3.3, p17
	// See if x >= 2
	cmp	r1, #0		// was MSB set?
	bge	SmallX
	movs	r4, #RECIPROCAL_GUESS_HI
	lsls	r4, #12		// approx. 5.69 p17
	subs	r4, r5		// 1/x < 1 guess, p20
	lsrs	r4, #5		// guess p15
	b	Reciprocal

SmallX:
	movs	r4, #RECIPROCAL_GUESS_LO
	lsls	r4, #11		// approx. 2.92 p17
	subs	r4, r5		// 1/x < 1 guess, p18
	lsrs	r4, #3		// guess p15
Reciprocal:
	// Start Newton-Raphson iterations
	// error e = guess*x - 1
	// next = guess - guess*e
	// 
	// r5 = x p17
	// r4 = guess p15
	muls	r5, r4		// e = guess * x - 1 p32
	asrs	r5, #15		// e p17
	muls	r5, r4		// guess * e p32
	asrs	r5, #17		// guess * e p15
	subs	r4, r5		// guess -= guess * e = new guess p15

	// round two, gets us to 15 bits
	lsrs	r5, r1, #13	// x p17
	muls	r5, r4		// e = x*guess - 1 p32
	asrs	r5, #15		// e p17
	muls	r5, r4		// guess*e p32
	asrs	r5, #17		// guess*e p15
	subs	r4, r5		// final approximation of 1/x p15

	// r0 = y p30
	// r1 = x p30
	// r2 = z p32 or p38
	// r3 = exponent difference
	// r4 = approximation of 1/x p15
	// r12 = octant info
	//
	// q0 = y*guess, rough quotient (14+ bits)
	// rem = y - q0*x, exact remainder from q0
	// q1 = guess*rem, quotient from remainder (approx rem/x)
	// quo = q0 + q1

	asrs	r6, r0, #15	// y p15
	muls	r6, r4		// y*guess = approx quotient q0 p30
	asrs	r6, #15		// q0 p15
	lsrs	r5, r1, #2	// x p28
	muls	r5, r6		// x*q0 p43
	lsls	r0, #13		// y p43
	subs	r5, r0, r5	// y - x*q0 = rem p43
	asrs	r5, #14		// rem p29
	muls	r5, r4		// rem*guess = q1 p44
	asrs	r5, #13		// q1 p31
	lsls	r6, #16		// q0 p31
	adds	r0, r6, r5	// q = q0 + q1 p31

	// r0 = y/x p31
	// r2 = z p32 or p38
	// r3 = exponent difference
	// r12 = octant info
	// if exponent difference > SMALL_ATAN_TABLE_START_I, z is p38

	movs	r4, #EXP_BIAS32
	subs	r3, #1
	bgt	TestSmallTable
	negs	r3, r3
	lsls	r0, r3		// align y/x with z
	b	Sum

TestSmallTable:
	subs	r4, r3
	cmp	r3, #SMALL_ATAN_TABLE_START_I - 1
	blt	Align
	subs	r3, #SMALL_ATAN_TABLE_SHIFT
Align:
	lsls	r2, r3		// align y/x with z
Sum:
	adds	r2, r0		// z + y/x, final atan mantissa

	// r2 = z (angle) p32
	// r12 = octant info
	mov	r7, r12		// get octant info
	
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
	cmp	r7, #2
	blt	NormLoop
	ldr	r0, =#PI_MANTISSA	// p30 for pi
	lsrs	r3, r7, #2	// isolate octant bit 2
	lsrs	r0, r3		// if 1xx, convert to pi/2
	movs	r5, #EXP_BIAS32 + 2
	subs	r5, r4
	movs	r4, #EXP_BIAS32 + 2
.ifndef	NO_DENORMALS
	// exponent difference can exceed 8 bits
	cmp	r5, #32		// shifting to zero?
	blt	1f
	movs	r2, #0
1:
.endif
	lsrs	r2, r5		// z p30
	cmp	r7, #6
	bge	AddCorrection
	negs	r2, r2		// subtract instead
AddCorrection:
	adds	r2, r0

	// Normalize the z result in r2.
NormLoop:
	subs	r4, #1
	adds	r2, r2
	bcc	NormLoop	// until we shift off MSB

	// r2 = z
	// r4 = exponent of z
	// r7 = octant info
PositionExp:
	lsls	r0, r4, #MANT_BITS32	// position exponent
	beq	RoundChk
	bmi	TinyResult
Pack:
	lsrs	r2, #EXP_BITS32 + 1	// position mantissa
	adcs	r0, r2		// combine exponent, inc. rounding bit
SetSign:
	lsls	r7, #31		// original sign of y
	orrs	r0, r7		// sign of result is sign of y
	pop	{r4-r7, pc}

.ifdef NO_DENORMALS
RoundChk:
	// see if if could round up to a normal number
	movs	r4, 1		//  exponent if round up works
	MOV_IMM	r3, 0x200
	adds	r2, r3
	beq	PositionExp
TinyResult:
.else
RoundChk:
TinyResult:
	// result is tiny
	negs	r4, r4
	cmp	r4, #25		// shifting to zero?
	bhs	ReturnZero
	lsrs	r2, #1		// make room for mantissa MSB, no longer implied
	movs	r1, #1
	lsls	r1, #31
	orrs	r2, r1		// set result MSB
	lsrs	r2, r4		// denormalize
	movs	r0, #0		// zero exponent
	b	Pack

.endif
ReturnZero:
	movs	r0, #0
	b	SetSign

	.endfunc
