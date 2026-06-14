//****************************************************************************
// expf.s
//
// Created 6/8/2026 12:40:45 PM by Tim Paterson
//
//****************************************************************************

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


//****************************************************************************
// 32-bit floating-point exponential
//
// Entry:
//	r0 = input x
// Exit:
//	r0 = e^x
//
// The calculation uses Feynman's logarithm algorithm, backward (see logf()).
// The basic concept is to find a set of terms t from the table of logs that
// total to x. For each t, we multiply by e^t (that is, what t is the log of).
// The terms are log(1 + 2^-k) for k = 1..kmax. To multiply m by 1 + 2^-k we
// use m + (m >> k).
//
// for (m = 1, k = 1, s = 0; k < kmax; k++)
// {
//   tmp = s + ln(1 + 2^-k); [from table]
//   if (tmp <= x)
//   {
//     // accept term, multiply
//     s = tmp;
//     m += m >> k
//   }
// }
// return m;
//
//****************************************************************************

.set	LN2,		0xB17217F8		// ln(2) p32
.set	LN2p30,		((LN2 >> 1) + 1) >> 1	// ln(2) p30
.set	LOG2_E,		0xB8AA3B29		// log2(e) (= 1/ln(2)) p31
.set	LOG2_Ep12,	((LOG2_E >> 18) + 1) >> 1 //log2(e) p12
.set	LOG_ENTRIES,	14
.set	MAX_EXPONENT,	7


	.func	__expfM0

BigExp:
	// r0 = input
	// r1 =  exponent - (EXP_BIAS32 + MAX_EXPONENT)
	// r2 =  sign, 0 or -1
	cmp	r1, #EXP_SPECIAL32 - (EXP_BIAS32 + MAX_EXPONENT)
	beq	SpecialExp
	cmp	r2, #0		// check sign
	bmi	ReturnZero
ReturnInfinity:
	MOV_IMM	r0, INFINITY32
	pop	{r4-r5, pc}

SpecialExp:
	// if -infinity, return 0
	// if +infinity or NAN, return that
	lsls	r1, r0, #EXP_BITS32 + 1
	bne	ReturnOp	// not zero is a NAN
	cmp	r2, #0		// check sign
	bpl	ReturnOp	// e^+infinity = +infinity
ReturnZero:
	movs	r0, #0		// e^-infinity = 0
ReturnOp:
	pop	{r4-r5, pc}


ENTRY_POINT	__expfM0, expf
	push	{r4-r5, lr}
	asrs	r2, r0, #31	// copy sign, extended
	lsls	r1, r0, #1	// clear input sign
	lsrs	r1, #MANT_BITS32 + 1	// input exponent
	subs	r1, #EXP_BIAS32 + MAX_EXPONENT
	bge	BigExp
	lsls	r0, #EXP_BITS32	// clear off exponent
	MOV_IMM	r3, 1 << 31	// implied bit position
	orrs	r0, r3		// Set implied bit
	lsrs	r0, #8		// x p(23 - exponent)
	eors	r0, r2
	subs	r0, r2		// 2's complement
	negs	r1, r1		// shift count
	// calculate exponent of result
	// r1 = MAX_EXPONENT - exponent
	MOV_IMM	r3, LOG2_Ep12	// log2(e) p12
	asrs	r2, r0, #23 - (10 + MAX_EXPONENT) // x p(10 + MAX_EXPONENT - exponent)
	asrs	r2, r1		// x p10
	muls	r2, r3		// log2(e^x) p22
	asrs	r2, #22		// new exponent p0
	// position argument fixed point p30
	subs	r1, #30 - 23 + MAX_EXPONENT
	bmi	LeftShift
	asrs	r0, r1		// x p30
	b	Shifted

LeftShift:
	negs	r1, r1
	lsls	r0, r1		// x p30
Shifted:
	// effect of exponent on mantissa
	MOV_IMM	r3, LN2p30	// ln(2) p30
	muls	r3, r2		// ln(2) * exponent p30
	subs	r1, r0, r3	// s = remainder p30
	bpl	HaveExp
	// exponent guess was too big, bump it down
	subs	r2, #1
	MOV_IMM	r3, LN2p30	// ln(2) p30
	adds	r1, r3
HaveExp:
	MOV_IMM	r0, 1 << 30	// m = 1 p30
	movs	r5, #1		// k = 1 (shift count)
	ldr	r3, =#__logtablef
	lsls	r1, #2		// s p32
ExpLoop:
	// r0 = exponential m p30
	// r1 = remainder s p32
	// r2 = exponent
	// r3 = table of logs
	// r5 = shift count
	ldmia	r3!, {r4}
	subs	r4, r1, r4	// t = s - table[i]
	bcc	NoFit
	movs	r1, r4		// s = t
	movs	r4, r0
	lsrs	r4, r5		// m >> k
	adcs	r0, r4		// m += m >> k
NoFit:
	adds	r5, #1
	cmp	r5, #LOG_ENTRIES
	blt	ExpLoop

	// r0 = m p30
	// r1 = s, near zero p32
	// r2 = exponent
	//
	// We need to multiply m by e^s. Since s is close to zero,
	// a first order approximation is 1 + s.
	lsrs	r4, r0, #18	// m p12
	asrs	r3, r1, #2	// s p30
	muls	r4, r3		// m * s p42
	asrs	r4, #12		// m * s p30
	adcs	r0, r4		// m + m*s
	bmi	Normalized
NormLoop:
	subs	r2, #1
	adds	r0, r0
	bpl	NormLoop
Normalized:
	adds	r2, #EXP_BIAS32
.ifdef NO_DENORMALS
	blt	ReturnZero
.else
	blt	TinyResult
.endif
	cmp	r2, #EXP_SPECIAL32 - 1
	bge	ReturnInfinity
	lsls	r2, #MANT_BITS32	// position exponent
	lsrs	r0, #EXP_BITS32		// position mantissa
	adcs	r0, r2
	pop	{r4-r5, pc}


.ifndef NO_DENORMALS

TinyResult:
	// r0 = result, left justified
	// r2 = biased result exponent - 1 (negative)
	movs	r1, #EXP_BITS32
	subs	r1, r2
	movs	r3, #0
	lsrs	r0, r1
	adcs	r0, r3
	pop	{r4-r5, pc}

.endif

	.endfunc
