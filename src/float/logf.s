//****************************************************************************
// logf.s
//
// Created 5/23/2026 6:20:59 PM by Tim Paterson
//
//****************************************************************************

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


//****************************************************************************
// 32-bit floating-point natural logarithm
//
// Entry:
//	r0 = input
// Exit:
//	r0 = natural log
//
// The calculation uses Feynman's logarithm algorithm (Feynman has more than
// one algorithm). The basic concept is to find a set of factors for the input,
// and find its log by summing the (pre-calculated) logs of those factors.
//
// The input is restricted to 1 <= x < 2 (the definition of the mantissa).
// The factors are 1 + 2^k, k starting at 1; implemented as m + (m >> k).
//
// for (m = 1, k = 1, s = 0; k < kmax; k++)
// {
//   t = m + (m >> k)
//   if (t <= x)
//   {
//     // accept factor, sum its log
//     m = t;
//     s += ln(1 + 2^-k); [from table]
//   }
// }
// return s;
//
// We make some adjustments to the form above. The initial value for m is the
// argument x, and the target value is 2. This means the we're finding
// ln(2/x) = ln(2) - ln(x). So subtracting the result from ln(2) gives ln(x).
// We can do this in the loop by initializing the sum to ln(2), and then
// subtracting (instead of adding) each accepted log.
//****************************************************************************

.set	LN2,			0xB17217F8	// ln(2) p32
.set	LOG_ENTRIES,		16
.set	MAX_LEADING_ZEROS,	6		// not including implied bit


ReturnNan:
	ldr	r0, =#NAN32
	pop	{r4-r7, pc}

ReturnMinusInf:
	ldr	r0, =#INFINITY32 | SIGN_BIT32
	pop	{r4-r7, pc}


FUNC_START	__logfM0, logf
	push	{r4-r7, lr}
	lsls	r1, r0, #1		// clear input sign
	beq	ReturnMinusInf		// must not be zero
	bcs	ReturnNan		// must not be negative
	lsrs	r1, #MANT_BITS32 + 1	// input exponent
.ifndef NO_DENORMALS
	beq	Denormal
.endif
	cmp	r1, #EXP_SPECIAL32
	beq	Exit		// return NAN or +Infinity
	subs	r1, #EXP_BIAS32
	lsls	r0, #EXP_BITS32	// normalize, clearing exponent (x p31)
	lsls	r2, r0, #1	// clear last exponent bit (MSB of mantissa)
	asrs	r7, r2, #32 - MAX_LEADING_ZEROS
	orrs	r7, r1
	beq	OverOne
	asrs	r7, r2, #32 - MAX_LEADING_ZEROS + 1
	ands	r7, r1
	mvns	r2, r7
	beq	UnderOne
	// Set implied bit
	MOV_IMM	r2, 1 << 31
	orrs	r0, r2
Normalized:
	// r0 = x = input mantissa with implied bit set, p31
	// r1 = exponent
	MOV_IMM	r2, LN2		// init s
	movs	r3, #1		// init k
	ldr	r4, =#__logtablef
LogLoop:
	// r0 = m p31
	// r1 = exponent
	// r2 = s p32
	// r3 = k
	// r4 = table of logs
	ldmia	r4!, {r6}	// load table entry
	movs	r5, r0		// m p31
	lsrs	r5, r3		// m * 2^-k p31
	adcs	r5, r0		// m * (1 + 2^-k) p31
	bcs	LowerTest
	// product fit, accept it
	subs	r2, r6
UpperTest:
	adds	r3, #1
	cmp	r3, #LOG_ENTRIES
	bgt	LogDone

	// start another loop, r0 & r5 swapped
	// r1 = exponent
	// r2 = s p32
	// r3 = k
	// r4 = table of logs
	// r5 = m p31
	ldmia	r4!, {r6}	// load table entry
	movs	r0, r5		// m p31
	lsrs	r0, r3		// m * 2^-k p31
	adcs	r0, r5		// m * (1 + 2^-k) p31
	bcs	UpperTest
	// product fit, accept it
	subs	r2, r6
LowerTest:
	adds	r3, #1
	cmp	r3, #LOG_ENTRIES
	ble	LogLoop
	movs	r5, r0
LogDone:
	// r1 = exponent
	// r2 = s p32
	// r5 = m p31
	//
	// We need one more factor f to mulitply m that makes m == 2,
	// then ln(x) = s - ln(f). That factor is f = 2/m, so
	//
	// ln(x) = s - ln(2/m) = s + ln(m/2)
	//
	// Since m is very close to 2 already, m/2 is very close to 1,
	// so the first order estimate of ln(m/2) is m/2 - 1.
	// r5 = m p31 == m/2 p32 which has no integer bits,
	// effectively subtracting 1.
	adds	r0, r2, r5	// ln(x) p32

	// Now factor in effect of binary exponent
	movs	r7, #0
	movs	r3, #32 - 24
	movs	r5, #0
	MOV_IMM	r2, LN2 >> 8	// ln(2) p24
	muls	r2, r1		// ln(exponent) p24
	beq	NoExp
	movs	r3, r2
	MOV_IMM	r4, LN2 & 0xFF
	muls	r4, r1		// ln(2) lowest 16 bits
	bmi	NormNeg
NormPos:
	adds	r5, #1
	lsls	r3, #1
	bpl	NormPos
	lsls	r2, r5
	movs	r1, #32 - 24
	subs	r1, r5
	asrs	r4, r1
	adds	r2, r4
	lsrs	r0, r1
	adds	r1, #EXP_BIAS32
	adds	r0, r2
	bcs	Combine
NormLoop:
	subs	r1, #1
	adds	r0, r0
	bcc	NormLoop
Combine:
	lsls	r7, #31			// get sign
	lsls	r1, #MANT_BITS32	// position exponent
	lsrs	r0, #EXP_BITS32 + 1	// position mantissa
	adcs	r0, r1
	adds	r0, r7
Exit:
	pop	{r4-r7, pc}

NoExp:
	movs	r1, #EXP_BIAS32
	b	NormLoop

NormNeg:
	adds	r5, #1
	lsls	r3, #1
	bmi	NormNeg
	lsls	r2, r5
	movs	r1, #32 - 24
	subs	r1, r5
	asrs	r4, r1
	adds	r2, r4
	lsrs	r0, r1
	adds	r1, #EXP_BIAS32
	adds	r0, r2
	negs	r0, r0
	subs	r7, #1		// r7 = -1 to flag negative result
	b	NormLoop


.ifndef NO_DENORMALS
Denormal:
	// r0 = x
	// r1 = exponent, currently zero
	movs	r4, r0		// pass value
	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r3, r7 preserved
	// r5, r6 trashed
	bl	__clz_denormal	// Get leading zeros
	lsls	r0, r4
	adds	r4, #(1 << (EXP_BITS32 - 1)) - 1 - (EXP_BITS32 + 1)
	negs	r1, r4
	b	Normalized
.endif

UnderOne:
	// r7 = -1
	movs	r1, #MAX_LEADING_ZEROS - 1
	lsls	r2, r0, #MAX_LEADING_ZEROS - 1
UnderOneNorm:
	movs	r0, r2		// save before shifting
	adds	r1, #1
	adds	r2, r2
	bmi	UnderOneNorm
	b	ComputeLog

OverOne:
	// r0 = x - 1 p31, at least 7 leading zeros
	movs	r1, #MAX_LEADING_ZEROS - 1
	lsls	r0, #MAX_LEADING_ZEROS
	beq	Exit		// exactly 1, return zero
OverOneNorm:
	adds	r1, #1
	adds	r0, r0
	bpl	OverOneNorm
	lsrs	r0, #1		// back up to previous
ComputeLog:
	// r0 = x (argument - 1) p(31 + r1) (= x/2 p32 or x/4 p33)
	//
	// log(1 + x) = x - x^2/2 + x^3/3 - x^4/4 ...
	// since x is small we'll use the first 4 terms
	// x - x * (x/2 - x*x*(1/3 - x/4)
	MOV_IMM	r4, 0xAAAAAAAB	// 1/3 p33
	movs	r2, r0
	asrs	r2, r1
	subs	r4, r2		// 1/3 - x/4 p33
	lsrs	r4, #16		// 1/3 - x/4 p17
	asrs	r2, r0, #16	// x p15
	muls	r4, r2		// x/3 - x^2/4 p32
	asrs	r4, #16		// x/3 - x^2/4 p16
	muls	r4, r2		// x^2/3 + x^3/4 p(31+r1)
	lsrs	r4, r1		// x^2/3 + x^3/4 p31
	asrs	r2, r0, #1	// x/2 p31
	subs	r3, r2, r4	// x/2 - x^2/3 + x^3/4 p31
	mul32sx32shi	r3, r0, r3, r2, r4, r5	// x^2/2 + x^3/3 - x^4/4 p(30+r1)
	subs	r1, #1
	asrs	r3, r1		// x^2/2 + x^3/3 - x^4/4 p31
	negs	r1, r1
	adds	r1, #EXP_BIAS32
	subs	r0, r3		// x - x^2/2 + x^3/3 - x^4/4 p31
	eors	r0, r7
	subs	r0, r7
	b	NormLoop

	.endfunc
