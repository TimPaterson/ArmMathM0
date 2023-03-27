
/*
 * ddiv.s
 *
 * Created: 10/17/2021 4:55:10 PM
 *  Author: Tim
 */

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


// 64-bit IEEE floating-point divide
//
// Entry:
//	r1:r0 = num
//	r3:r2 = den
// Exit:
//	r1:r0 = num / den
//
// The calculation will use iteration to refine an approximations of the 
// reciprocal of the denominator (saw it on Wikipedia).
// The initial guess will be calculated by subtracting the upper mantissa
// bits from the constant 2.92, or 0xBB. The value was determined using a
// spreadsheet. It gives a result accurate to almost 4 bits.

.set	GuessBase, 0xBB


	.func	__ddiv

.ifdef NO_DENORMALS

NumZeroExp:
	// r1:r0 = num
	// r3:r2 = den
	// r4 = num exponent (zero)
	// r6 = 0x80000000 (sign bit position)
	// r7 = max allowed exponent
	// r12 = result sign
	lsrs	r5, r3, #MANT_BITS_HI64	// den exponent
	beq	ReturnNan		// 0/0, return NAN
	cmp	r5, r7
	ble	ZeroResult
	// is den NAN?
	lsls	r4, r3, #(EXP_BITS64 + 1)
	orrs	r4, r2
	bne	ReturnDen	// yes, return the NAN
ZeroResult:
	movs	r0, #0
	movs	r1, #0
	b	SetSign

DenZeroExp:
	// r1:r0 = num
	// r3:r2 = den
	// r4 = num exponent
	// r5 = den exponent (zero)
	// r6 = 0x80000000 (sign bit position)
	// r7 = max allowed exponent
	// r12 = result sign
	cmp	r4, r7		// check num exponent
	bgt	SavedSign	// Return whatever num is, Infinity or NAN
	b	RetInfinity

.else	// NO_DENORMALS

NumZeroExp:
	// r1:r0 = num
	// r3:r2 = den
	// r4 = num exponent (zero)
	// r6 = 0x80000000 (sign bit position)
	// r7 = max allowed exponent
	// r12 = result sign
	movs	r4, r1
	orrs	r4, r0
	beq	NumIsZero
	// __dop1_normalize uses tailored calling convention
	// input: r1:r0 = op1
	// returns r4 = op1 exponent (< 0)
	// r5 trashed
	// all other registers preserved
	bl	__dop1_normalize
	str	r0, [sp]	// update saved value
	b	NumNormalized

DenZeroExp:
	// r1:r0 = num
	// r3:r2 = den
	// r4 = num exponent
	// r5 = den exponent
	// r6 = 0x80000000 (sign bit position)
	// r7 = max allowed exponent
	// r12 = result sign
	movs	r5, r3
	orrs	r5, r2
	beq	DenIsZero
	// __dop2_normalize uses tailored calling convention
	// input: r3:r2 = op2
	// returns r5 = op2 exponent (< 0)
	// all other registers preserved
	bl	__dop2_normalize
	str	r2, [sp, #4]	// update saved value
	b	DenNormalized

DenIsZero:
	cmp	r4, r7		// check num exponent
	bgt	SavedSign	// Return whatever num is, Infinity or NAN
	b	RetInfinity

NumIsZero:
	lsrs	r5, r3, #MANT_BITS_HI64	// den exponent
	bne	DenNotZero
	movs	r4, r3
	orrs	r4, r2
	beq	ReturnNan	// 0/0, return NAN
DenNotZero:
	cmp	r5, r7
	ble	ZeroResult
	// is den NAN?
	lsls	r4, r3, #(EXP_BITS64 + 1)
	orrs	r4, r2
	bne	ReturnDen
ZeroResult:
	movs	r0, #0
	movs	r1, #0
	b	SetSign

.endif	// else NO_DENORMALS

DenSpclExp:
	// r1:r0 = num
	// r3:r2 = den
	// r4 = num exponent
	// r5 = den exponent
	// r6 = 0x80000000 (sign bit position)
	// r7 = max allowed exponent
	// r12 = result sign
	//
	// mantissa == 0?
	lsls	r6, r3, #(EXP_BITS64 + 1)
	orrs	r6, r2
	bne	ReturnDen	// den is NAN, return it
	// Den is Infinity
	cmp	r4, r7		// num special?
	ble	ZeroResult	// zero if den is infinity & num normal
ReturnNan:
	ldr	r1, =#NAN64
	movs	r0, #0
	b	SetSign

ReturnDen:
	movs	r0, r2
	movs	r1, r3
SavedSign:
	b	SetSign


ENTRY_POINT	__ddiv, __aeabi_ddiv
	push	{r0, r2, r4-r7, lr}
	// compute final sign
	movs	r6, #1
	lsls	r6, #31		// sign position
	movs	r7, r3
	eors	r7, r1
	ands	r7, r6		// final sign
	mov	r12, r7

	// r1:r0 = num
	// r3:r2 = den
	// r6 = 0x80000000 (sign bit position)
	// r12 = result sign

	// clear signs
	bics	r1, r6
	bics	r3, r6

	ldr	r7, =#EXP_SPECIAL64 - 1
	lsrs	r4, r1, #MANT_BITS_HI64	// num exponent
	beq	NumZeroExp
NumNormalized:
	lsrs	r5, r3, #MANT_BITS_HI64	// den exponent
	beq	DenZeroExp
DenNormalized:
	cmp	r5, r7
	bgt	DenSpclExp
	cmp	r4, r7
	bgt	SavedSign	// just return num if special

	// r1:r0 = num
	// r3:r2 = den
	// r4 = num exponent
	// r5 = den exponent
	// r12 = result sign

	subs	r4, r5		// compute exponent, unbiased
	mov	lr, r4		// save exponent

	// Clear exponent, set implied bit
	lsls	r1, #EXP_BITS64
	lsls	r3, #EXP_BITS64
	orrs	r1, r6
	orrs	r3, r6
	// add lower bits to upper words
	lsrs	r6, r0, #32 - EXP_BITS64
	orrs	r1, r6
	lsrs	r6, r2, #32 - EXP_BITS64
	orrs	r3, r6

	// r0 = num p52
	// r1 = num p31 (lower bits overlap r0)
	// r2 = den p52
	// r3 = den p31 (lower bits overlap r2)
	// r12 = result sign
	// lr = result exponent
	//
	// Compute guess for 1/den = (K - den)/2. K is nearly 3.
	// den in [1, 2). The "p" notation is the position of the
	// binary point (p16 means there are 16 bits to the right).
	lsrs	r4, r3, #15	// den p16
	movs	r5, #GuessBase
	lsls	r5, #25 - 15	// MSB one bit left of den
	subs	r5, r4		// x p17, < 1
	lsrs	r5, #1		// x p16

	// Use iteration for refining the guess for 1/den. This algorithm
	// cubes the error (triples the number of bits) on each iteration.
	// (Newton-Raphson squares the error/doubles the bits per iteration.)
	//
	// next = x - x*(d*x - 1) + x*(d*x - 1)^2
	//
	// refactored as:
	//
	// next = x - x*((d*x - 1) - (d*x - 1)^2)
	//
	// d*x is very close to 1. We calculate it p32 or greater so the
	// leading 1, if present, just drops off. If it is less than 1, we
	// treat the result as a signed (now negative) number, also
	// effectively subtracting 1.

	// r0 = num p52
	// r1 = num p31 (lower bits overlap r0)
	// r2 = den p52
	// r3 = den p31 (lower bits overlap r2)
	// r4 = den p16
	// r5 = x p16
	// r12 = result sign
	// lr = result exponent
	muls	r4, r5		// d*x - 1 p32, call it e (error)
	asrs	r6, r4, #16	// e p16
	muls	r6, r6		// e^2 p32
	subs	r4, r6		// e - e^2 p32
	asrs	r4, #16		// e - e^2 p16
	muls	r4, r5		// x*(e - e^2) p32
	asrs	r4, #16		// x*(e - e^2) p16
	subs	r5, r4		// x - x*(e - e^2) p16

	// We have about 11 bits for x = 1/den, meaning e = d*x - 1 has
	// 11 leading zeros.
	lsrs	r4, r3, #2	// den p29
	lsrs	r5, #5		// x p11
	muls	r4, r5		// d*x - 1 p40, call it e (error)
	asrs	r6, r4, #15	// e p25
	muls	r6, r6		// e^2 p50
	lsrs	r6, #10		// e^2 p40
	subs	r4, r6		// e - e^2 p40
	asrs	r4, #11		// e - e^2 p29
	muls	r4, r5		// x*(e - e^2) p40
	asrs	r4, #9		// x*(e - e^2) p31
	lsls	r5, #20		// x p31
	subs	r5, r4		// x - x*(e - e^2) p31

	// r0 = num p52
	// r1 = num p31 (lower bits overlap r0)
	// r2 = den p52
	// r3 = den p31 (lower bits overlap r2)
	// r5 = x p31 (reciprocal estimate)
	// r12 = result sign
	// lr = result exponent
	//
	// compute quotient
	// q0 = x*(num hi32), rough quotient (27+ bits)
	// result p31 * p31 = p62, lower 32 bits discarded for p30
	// lowest partial product not needed

	lsrs	r6, r5, #16	// xH
	uxth	r7, r1		// numL
	muls	r7, r6		// xH * numL = mid 1
	lsrs	r4, r1, #16	// numH
	muls	r6, r4		// xH * numH = hi
	lsrs	r1, r7, #16	// hi half of mid 1
	adds	r6, r1
	uxth	r1, r5		// xL
	muls	r1, r4		// xL * numH = mid 2
	uxth	r7, r7		// lo half of mid1
	adds	r1, r7		// sum mids
	lsrs	r1, #16
	adds	r4, r6, r1	// q0 = x*num p30

	// r0 = num p52
	// r2 = den p52
	// r3 = den p31 (lower bits overlap r2)
	// r4 = q0 p30
	// r5 = x p31 (reciprocal estimate)
	// r12 = result sign
	// lr = result exponent
	//
	// Compute q0*den exactly, except upper bits aren't needed since
	// they will be the same as num. We already tossed upper bits of num.

	mul32x32 r4, r2, r7, r2, r1, r6, r0	// r2:r7 = lo product

	ldr	r0, [sp]	// recover num p52
	lsrs	r1, r3, #EXP_BITS64	// den p20
	muls	r1, r4		// hi product, upper bits discarded
	adds	r2, r1		// r2:r7 = q0*den p82
	// rem = num - q0*den, exact remainder from q0
	lsls	r2, #7
	lsrs	r7, #32 - 7
	orrs	r2, r7
	lsls	r7, r0, #5	// num p57
	subs	r1, r7, r2	// rem p57

	// r0 = num p52
	// r1 = rem p57
	// r3 = den p31
	// r4 = q0 p30
	// r5 = x p31 (reciprocal estimate)
	// r12 = result sign
	// lr = result exponent
	//
	// q1 = x*rem, quotient from remainder (approx rem/den)
	// Note this macro multiplies unsigned * signed.

	mul32x32s r5, r1, r5, r1, r2, r6, r7	// r1 = q1 p56

	// quo = q0 + q1
	lsrs	r5, r4, #6	// q0 p24
	lsls	r4, #32 - 6	// q0 p56
	asrs	r6, r1, #31	// sign extend q1
	adds	r4, r1
	adcs	r5, r6		// r5:r4 = quo p56

	// r0 = num p52
	// r3 = den p31
	// r5:r4 = quo p56
	// r12 = result sign
	// lr = result exponent

	mov	r2, lr		// unbiased exponent
	lsls	r6, r5, #8	// normalized?
	bcs	Normalized
	// shift quo & num for normalization
	lsl64const r4, r5, 1
	lsls	r0, #1
	subs	r2, #1		// adjust exponent
Normalized:
	ldr	r6, =#EXP_BIAS64
	adds	r2, r6		// add bias
	subs	r2, #1		// biased exponent - 1
	adds	r6, r6		// max exponent (0x7FE)
	lsls	r7, r2, #MANT_BITS_HI64	// exponent final position
	mov	lr, r7
	cmp	r2, r6		// r6 = max exponent
	bhs	BigExp		// catches exp < 0 too

	// Result quotient is accurate, but rounding is tricky because
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

	adds	r4, #4		// add to guard bit in quo
	bcc	1f
	adds	r5, #1
1:
	lsrs	r6, r4, #4	// check if rounding needed
	bcc	NoRound

	// r0 = num p52
	// r3 = den p31
	// r5:r4 = quo p56
	// r12 = result sign
	// lr = exponent in final position
	//
	// Compute rem = num - quo*den, except upper bits aren't needed
	// (they're zero). We already tossed upper bits of num.
	// If rem >= den / 2, then round up.
	// Including the rounding bit in quo, which is 1, we're computing
	// num - (quo + 0.5)*den = rem - den/2, so a non-negative result
	// means round up.
	lsls	r0, #24		// num p76
Remainder:
	lsrs	r4, #3
	lsls	r4, #3		// zero out bits below rounding bit
	lsrs	r3, #11		// restore den p20
	muls	r3, r4		// denH * quoL p76
	subs	r0, r3
	movs	r1, r5		// quoH p24
	ldr	r2, [sp, #4]	// denL p52
	muls	r1, r2		// quoH * denL p76
	subs	r0, r1
	mul32x32 r2, r4, r2, r3, r1, r6, r7	// r3:r2 = quoL * denL p108
	negs	r2, r2
	sbcs	r0, r3
RemTest:
	bmi	NoRound
.ifndef NO_DENORMALS
	beq	RoundEven	// round even if remainder is zero
.endif
	// If the mantissa is all ones, this will round up into the exponent
	// field, incrementing it correctly. If that in turn becomes the max
	// exponent, it will be correctly formatted as infinity.
RoundUp:
	adds	r4, #0x10	// round up
	bcc	NoRound
	adds	r5, #1
NoRound:
	// r5:r4 = quo p56
	// r12 = result sign
	// lr = exponent in final position
	lsrs	r0, r4, #4
	lsrs	r1, r5, #4
	lsls	r5, #32 - 4
	orrs	r0, r5
	add	r1, lr		// combine exponent
SetSign:
	add	r1, r12		// combine sign
	pop	{r2-r7, pc}

.ifndef NO_DENORMALS
RoundEven:
	cmp	r2, #0		// check low half of remainder
	bne	RoundUp
	// Remainder is exactly zero. We're halfway, so round even.
	lsrs	r0, r4, #5	// final LSB to CY
	bcs	RoundUp
	b	NoRound
.endif

RetInfinity:
	// Build infinity
	ldr	r1, =#INFINITY64
	movs	r0, #0
	b	SetSign

BigExp:
	// r0 = num p52
	// r2 = result exponent - 1
	// r3 = den p31
	// r5:r4 = quo p55
	// r12 = result sign
	// lr = exponent in final position
	bge	RetInfinity
.ifdef NO_DENORMALS
	// See if it could round up
	adds	r6, r2, #1	// was exponent -1?
	bne	ReturnZero
	adds	r4, #0x10	// round up
	bcs	1f
	adds	r4, #4		// try a bigger nudge
1:
	adcs	r5, r6		// r6 == 0
	lsls	r3, r5, #EXP_BITS64 - 4
	bcs	NoRound		// it rounded up
ReturnZero:
	b	ZeroResult
.else
	// Denormalize
	//
	// If we're losing lots of bits, we'll just round with the ones
	// we have using the shared denormalizer. Otherwise, we'll adjust
	// precision and go through the remainder calculation.
	negs	r6, r2		// count to denormalize by
	cmp	r6, #32
	bgt	DenormHelp
	// 64-bit right shift by count in r6
	adds	r2, #32
	lsrs	r4, r6
	movs	r7, r5
	lsrs	r5, r6
	lsls	r7, r2
	orrs	r4, r7

	movs	r1, #0
	mov	lr, r1		// exponent is zero

	// See if we need to compute remainder for rounding
	adds	r4, #4		// add to guard bit in quo
	bcc	1f
	adds	r5, #1
1:
	lsrs	r7, r4, #4	// check if rounding needed
	bcc	NoRound
	// Effectively shift num in r0 right the same amount by reducing
	// it's normal left shift of 24.
	subs	r2, #32 - 24
	blt	LongDenorm	// whoops, really need to shift num right
	lsls	r0, r2
	b	Remainder

LongDenorm:
	// shift num right instead of left
	negs	r6, r2
	adds	r2, #32
	movs	r7, r0
	lsls	r7, r2		// save low bits of num
	lsrs	r0, r6
	// start our own version of remainder calc
	lsrs	r4, #3
	lsls	r4, #3		// zero out bits below rounding bit
	lsrs	r3, #11		// restore den p20
	muls	r3, r4		// denH * quoL p76
	subs	r0, r3
	ldr	r2, [sp, #4]	// denL p52
	// quoH is zero, so skip that multiply
	push	{r6, r7}
	mul32x32 r2, r4, r2, r3, r1, r6, r7	// r3:r2 = quoL * denL p108
	pop	{r6, r7}
	// r6 = amount num shifted right
	// r7 = num extension shifted off
	subs	r2, r7, r2
	sbcs	r0, r3		// calculate final remainder
	// Upper bits of rem are not valid because we shifted in zeros
	// when num was shifted right. Discard those bits.
	lsls	r0, r6		// upper bits invalid
	b	RemTest

DenormHelp:
	lsrs	r0, r4, #4
	lsrs	r1, r5, #4
	lsls	r5, #32 - 4
	orrs	r0, r5
	lsls	r4, #32 - 4	// sticky bits
	bl	__ddenormal_result
	b	SetSign
.endif

	.endfunc
