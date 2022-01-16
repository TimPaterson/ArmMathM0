
/*
 * fdiv.s
 *
 * Created: 8/20/2021 1:20:56 PM
 *  Author: Tim
 */ 

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


// 32-bit IEEE floating-point divide
//
// Entry:
//	r0 = num
//	r1 = den
// Exit:
//	r0 = num / den
//
// The calculation will use Newton-Raphson iteration on reciprocal.
// The initial guess will be calculated by subtracting the upper mantissa 
// bits from the constant 2.92, or 0xBB. The value was determined using a 
// spreadsheet. It gives a result accurate to almost 4 bits.

.set	GuessBase, 0xBB


FUNC_START	__fdiv, __aeabi_fdiv
.ifdef NO_DENORMALS
	push	{r4, r5}
.else
	push	{r4-r6, lr}
.endif
	// compute final sign
	movs	r5, #1
	lsls	r5, #31		// sign position
	movs	r3, r1
	eors	r3, r0
	ands	r3, r5		// final sign
	mov	r12, r3

	// clear signs
	bics	r0, r5
	bics	r1, r5

	lsrs	r2, r0, #MANT_BITS32	// num exponent
	beq	NumZeroExp
NumNormalized:
	lsrs	r3, r1, #MANT_BITS32	// den exponent
	beq	DenZeroExp
DenNormalized:

	// r0 = num
	// r1 = den
	// r2 = num exponent
	// r3 = den exponent
	// r5 = 0x80000000 (sign bit position)
	// r12 = final sign

	cmp	r3, #EXP_SPECIAL32
	beq	DenSpclExp
	cmp	r2, #EXP_SPECIAL32
	beq	SetSign			// return num if special

	subs	r2, r3			// compute exponent, unbiased
	adds	r2, #EXP_BIAS32 - 2	// r2 = biasd exponent - 1

	// Clear exponent, set implied bit
	lsls	r0, #EXP_BITS32
	lsls	r1, #EXP_BITS32
	orrs	r0, r5
	orrs	r1, r5

	// Compute guess for 1/den = (K - den)/2. K is nearly 3.
	// den in [1, 2). The "p" notation is the position of the
	// binary point (p16 means there are 16 bits to the right).
	lsrs	r3, r1, #15	// den p16
	movs	r4, #GuessBase
	lsls	r4, #25 - 15	// MSB one bit left of den
	subs	r4, r3		// x p17, < 1
	lsrs	r4, #1		// x p16

	// Use Newton-Raphson iteration for refining the guess for 1/den.
	// Using this method, the error is squared (number of bits doubled)
	// on each iteration, and will require two iterations to get 15 bits. 
	// (There is another method that converges faster [cube error/triple 
	// the bits], but it doesn't help because 1 iteration wouldn't be
	// enough and it's more work.) One iteration (d = den, x = 1/den guess):
	//
	// next = x - x*(d*x - 1)
	//
	// d*x is very close to 1. We calculate it p32 so the leading 1,
	// if present, just drops off. If it is less than 1, we treat the
	// result as a signed (now negative) number, also effectively
	// subtracting 1.

	// r0 = num p31
	// r1 = den p31
	// r2 = exponent - 1
	// r3 = den p16
	// r4 = x p16
	muls	r3, r4		// d*x - 1 p32, call it e (error)
	asrs	r3, #16		// e p16
	muls	r3, r4		// x*e p32
	asrs	r3, #16		// x*e p16
	subs	r4, r3		// x - x*e  p16

	// round two, gets us to 15 bits
	lsrs	r3, r1, #15	// den p16
	muls	r3, r4		// d*x - 1 p32, e
	asrs	r3, #16		// e p16
	muls	r3, r4		// x*e p32
	asrs	r3, #16		// x*e p16
	subs	r4, r3		// x - x*e  p16

	// compute quotient
	// r0 = num p31
	// r1 = den p31
	// r2 = exponent - 1
	// r4 = x p16 (reciprocal estimate)
	//
	// q0 = x*num, rough quotient (14+ bits)
	// rem = num - q0*den, exact remainder from q0
	// q1 = x*rem, quotient from remainder (approx rem/den)
	// quo = q0 + q1
	lsrs	r3, r0, #16	// num p15
	muls	r3, r4		// num*x = approx quotient q0 p31
	lsrs	r3, #16		// q0 p15
	lsrs	r5, r1, #8	// den p23
	muls	r5, r3		// den*q0 p38
.ifndef NO_DENORMALS
	movs	r6, r0		// save num p31 for denormal case
.endif
	lsls	r0, #7		// num p38
	subs	r5, r0, r5	// num - den*q0 = rem p38
	asrs	r5, #10		// rem p28
	muls	r5, r4		// rem*x = q1 p44
	asrs	r5, #14		// q1 p30
	lsls	r3, #15		// q0 p30
	adds	r3, r5		// q = q0 + q1 p30

	// Result quotient is very accurate, but rounding is tricky because
	// the error, no matter how small, can straddle a rounding boundary.
	// First check to see if it does by looking at the rounding bit and
	// the guard bit below it:
	//
	// 00 - never round up
	// 01 - maybe round up
	// 10 - maybe round up
	// 11 - always round up
	//
	// This is tested by adding 1 to the guard bit. This will leave the
	// rounding and guard bits:
	//
	// 01 - never round up
	// 10 - maybe round up
	// 11 - maybe round up
	// 00 - already rounded up
	//
	// So if the round bit ends up 1, we need to calculate the final 
	// remainder for rounding.
	//
	// The positions of these bits depends on whether the quotient
	// came out normalized.

	// r0 = num p38
	// r1 = den p31
	// r2 = exponent - 1
	// r3 = quo p30
	// r4 = x p16
	// r6 = num p31 if denormal build
	lsls	r5, r3, #2	// Normalized?
	bcs	Normalized
	cmp	r2, #EXP_SPECIAL32 - 1
	bhs	BigExpNorm	// catches exp < 0 too
	// Set up to compute remainder for rounding
	adds	r3, #0x10	// add to guard bit
	lsrs	r5, r3, #6	// quo p23 normalized
	bcc	Aligned		// Not near rounding boundary
	lsrs	r3, #5		// quo p25
	lsls	r0, #10		// num p48
	b	Remainder

Normalized:
	adds	r2, #1		// bump exponent
	cmp	r2, #EXP_SPECIAL32 - 1
	bhs	BigExp		// catches exp < 0 too
	// Set up to compute remainder for rounding
	adds	r3, #0x20	// add to guard bit
	lsrs	r5, r3, #7	// quo p23
	bcc	Aligned		// Not near rounding boundary
	lsrs	r3, #6		// quo p24
	lsls	r0, #9		// num p47
Remainder:
	// rem = num - quo*den
	// If rem >= den / 2, then round up.
	// Including the rounding bit in quo, which is 1, we're computing
	// num - (quo + 0.5)*den = rem - den / 2, so a non-negative result
	// means round up.
	lsrs	r1, #8		// den p23
	muls	r1, r3		// den*quo p47/48
	subs	r0, r1		// remainder p47/48
	bmi	Aligned
RoundUp:
	// If the mantissa is all ones, this will round up into the exponent
	// field, incrementing it correctly. If that in turn becomes the max
	// exponent, it will be correctly formatted as infinity.
	adds	r5, #1		// round up
Aligned:
	lsls	r2, #MANT_BITS32
AddExp:
	adds	r0, r2, r5
SetSign:
	add	r0, r12		// combine sign bit
.ifdef NO_DENORMALS
	pop	{r4, r5}
	bx	lr
.else
	pop	{r4-r6, pc}
.endif

DenSpclExp:
	// r0 = num
	// r1 = den
	// r2 = num exponent
	// r3 = den exponent
	// r5 = 0x80000000 (sign bit position)
	// r12 = final sign
	//
	// mantissa == 0?
	lsls	r4, r1, #(EXP_BITS32 + 1)
	bne	ReturnDen	// den is NAN, return it
	// Den is Infinity
	// if (expNum == EXP_SPECIAL)
	cmp	r2, #EXP_SPECIAL32
	bne	ZeroResult	// zero if den is infinity, num normal
ReturnNan:
	ldr	r0, =#NAN32	// num is infinity or NAN
	b	SetSign

ReturnDen:
	movs	r0, r1
	b	SetSign
	
.ifdef NO_DENORMALS

BigExpNorm:
	// r0 = num p38
	// r1 = den p31
	// r2 = exponent
	// r3 = quo p29
	// r4 = x p16
	bge	RetInfinity
	lsls	r3, #1		// quo p30
	b	RoundChk

BigExp:
	// r0 = num p38
	// r1 = den p31
	// r2 = exponent
	// r3 = quo p30
	// r4 = x p16
	bge	RetInfinity
RoundChk:
	// See if it could round up
	adds	r2, #1		// was exponent -1?
	bne	ZeroResult
	// Try rounding it up
	adds	r3, #0x80	// treat LSB as rounding bit
	bpl	ZeroResult
	lsrs	r0, r3, #8	// quo p23
	b	SetSign

NumZeroExp:
	lsrs	r3, r1, #MANT_BITS32	// den exponent
	beq	ReturnNan		// 0/0, return NAN
	cmp	r3, #EXP_SPECIAL32
	bne	ZeroResult
	lsls	r4, r1, #(EXP_BITS32 + 1) // is den NAN?
	bne	ReturnDen		// yes, return the NAN
ZeroResult:
	movs	r0, #0
	b	SetSign

DenZeroExp:
	cmp	r2, #EXP_SPECIAL32	// check num exponent
	beq	SetSign			// Return whatever num is, Infinity or NAN
RetInfinity:
	// Build infinity
	movs	r0, #EXP_SPECIAL32
	lsls	r0, #MANT_BITS32
	b	SetSign

.else	// NO_DENORMALS

BigExp:
	// r1 = den p31
	// r2 = exponent
	// r3 = quo p30
	// r4 = x p16
	// r6 = num p31
	blt	DenormRound
	b	RetInfinity

BigExpNorm:
	// r1 = den p31
	// r2 = exponent
	// r3 = quo p29
	// r4 = x p16
	// r6 = num p31
	bge	RetInfinity
	lsls	r3, #1		// quo p30
	lsls	r6, #1		// num p32
DenormRound:
	// Set up to compute remainder for rounding
	// r1 = den p31
	// r2 = exponent
	// r3 = quo p30
	// r4 = x p16
	// r6 = num p31
	negs	r0, r2
	lsrs	r3, r0
	adds	r3, #0x20	// add to guard bit
	lsrs	r5, r3, #7	// shift off rounding bit
	bcc	DenormNoRound
	// Calculate the remainder, which requires adjustments to 
	// the binary point of the num and/or den to retain precision.
	lsrs	r3, #6		// clear off below rounding bit
	// In the mainline remainder calculation, we shift num 
	// left to p47. Here we reduce that by the amount of 
	// denormalization, but not below zero.
	adds	r2, #16
	bmi	AdjDen
	lsls	r6, r2		// adjust num binary point
	lsrs	r1, #8		// den p23
	b	CalcRem
AdjDen:
	// So we're leaving num at p31. In the mainline calc, we
	// shift den right 8 bits to p23 (keeping all significant
	// bits). But we've shifted so much off the quotient we
	// need to reduce that to leave quo * den at p48.
	adds	r2, #8
	bmi	DenormNoRound	// underflow, leave as zero
	lsrs	r1, r2		// adjust den binary point
CalcRem:
	muls	r1, r3		// den*quo
	movs	r2, #0		// exponent will be zero
	subs	r6, r1		// remainder
	bmi	AddExp
	bne	RoundUp
	// Remainder was zero, round even
	lsrs	r1, r5, #1	// move LSB into CY
	adcs	r5, r2		// r2 == 0, so add CY
	b	AddExp

DenormNoRound:
	movs	r0, r5
	b	SetSign
	
DenZeroExp:
	// r0 = num, not zero
	// r1 = den, sign cleared
	// r2 = num exponent
	// r3 = den exponent
	// r5 = 0x80000000 (sign bit position)
	// r12 = final sign
	lsls	r4, r1, #1
	beq	DenIsZero
	// den is denormal, so normalize it

	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r3, r7 preserved
	// r5, r6 trashed
	bl	__clz_denormal	// Get leading zeros in den
	subs	r4, #EXP_BITS32
	negs	r3, r4		// den exponent
	adds	r4, #1
	lsls	r1, r4
	// restore r5
	movs	r5, #1
	lsls	r5, #31		// sign position
	b	DenNormalized

NumZeroExp:
	// r0 = num
	// r1 = den
	// r2 = num exponent
	// r5 = 0x80000000 (sign bit position)
	// r12 = final sign
	lsls	r4, r0, #1
	beq	NumIsZero
	// num is denormal, so normalize it

	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r3, r7 preserved
	// r5, r6 trashed
	bl	__clz_denormal	// Get leading zeros in num
	subs	r4, #EXP_BITS32
	negs	r2, r4		// num exponent
	adds	r4, #1
	lsls	r0, r4
	// restore r5
	movs	r5, #1
	lsls	r5, #31		// sign position
	b	NumNormalized

DenIsZero:
	cmp	r2, #EXP_SPECIAL32	// check num exponent
	beq	SetSign			// Return whatever num is, Infinity or NAN
RetInfinity:
	// Build infinity
	movs	r0, #EXP_SPECIAL32
	lsls	r0, #MANT_BITS32
	b	SetSign

NumIsZero:
	lsrs	r3, r1, #MANT_BITS32	// den exponent
	bne	DenNotZero
	cmp	r1, #0
	beq	ReturnNan	// 0/0, return NAN
DenNotZero:
	cmp	r3, #EXP_SPECIAL32
	bne	ZeroResult
	// is den NAN?
	lsls	r4, r1, #(EXP_BITS32 + 1)
	bne	ReturnDen
ZeroResult:
	movs	r0, #0
	b	SetSign

.endif	// else NO_DENORMALS

	.endfunc
