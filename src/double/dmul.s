
/*
 * dmul.s
 *
 * Created: 10/7/2021 4:48:03 PM
 *  Author: Tim
 */ 

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


// 96-bit left shift macro
.macro	lsl96	lo, mid, hi, cnt, tmp
	lsls	\hi, #\cnt
	lsrs	\tmp, \mid, #32 - \cnt
	orrs	\hi, \tmp
	lsls	\mid, #\cnt
	lsrs	\tmp, \lo, #32 - \cnt
	orrs	\mid, \tmp
	lsls	\lo, #\cnt
.endm

// 64-bit IEEE floating-point multiply
//
// Entry:
//	r1:r0 = op1
//	r3:r2 = op2
// Exit:
//	r1:r0 = op1 * op2

	.func	__dmul

.ifdef NO_DENORMALS

Op1ZeroExp:
	// r1:r0 = op1
	// r3:r2 = op2
	// r4 = op1 exponent (zero)
	// r7 = max allowed exponent
	lsrs	r4, r3, #MANT_BITS_HI64	// op2 exponent
Op2ZeroExp:
	// r1:r0 = op1
	// r3:r2 = op2
	// r4 = exponent of other operand
	// r7 = max allowed exponent
	//
	// zero * infinity or zero * NAN?
	cmp	r4, r7		// check other op
	bhi	ReturnNan
	movs	r0, #0
	movs	r1, #0
	b	SavedSign

ReturnNan:
	ldr	r1, =#NAN64
	movs	r0, #0
	b	SavedSign

.else	// NO_DENORMALS

ZeroResult:
	movs	r0, #0
	movs	r1, #0
	b	SavedSign

Op2ChkZero:
	// op1 is special
	orrs	r2, r3
	beq	ReturnNan
	b	SavedSign		// not zero, return op1

Op1ChkZero:
	// op2 is special
	orrs	r0, r1
	bne	ReturnOp2	// not zero, return op2
ReturnNan:
	ldr	r1, =#NAN64	// 0*infinity or NAN, return NAN
	movs	r0, #0
	b	SavedSign

Op2ZeroExp:
	// r1:r0 = op1
	// r3:r2 = op2
	// r4 = op1 exponent
	// r5 = op2 exponent (zero)
	// r6 = 0x80000000 (sign bit position)
	// r7 = max allowed exponent
	// r12 = result sign
	cmp	r4, r7
	bgt	Op2ChkZero	// op1 special exponent
	movs	r5, r3
	orrs	r5, r2
	beq	ZeroResult	// op2 is zero
	// __dop2_normalize uses tailored calling convention
	// input: r3:r2 = op2
	// returns r5 = op2 exponent (< 0)
	// all other registers preserved
	bl	__dop2_normalize
	b	Op2Normalized

Op1ZeroExp:
	// r1:r0 = op1
	// r3:r2 = op2
	// r4 = op1 exponent (zero)
	// r6 = 0x80000000 (sign bit position)
	// r7 = max allowed exponent
	// r12 = result sign
	lsrs	r5, r3, #MANT_BITS_HI64	// op2 exponent
	cmp	r5, r7
	bgt	Op1ChkZero	// op2 special exponent
	movs	r4, r1
	orrs	r4, r0
	beq	ZeroResult	// op1 is zero
	// __dop1_normalize uses tailored calling convention
	// input: r1:r0 = op1
	// returns r4 = op1 exponent (< 0)
	// r5 trashed
	// all other registers preserved
	bl	__dop1_normalize
	b	Op1Normalized

.endif	// else NO_DENORMALS

Op2SpclExp:
	// mantissa == 0?
	lsls	r6, r3, #(EXP_BITS64 + 1)
	orrs	r6, r2
	beq	Op2Inf
ReturnOp2:
	movs	r0, r2
	movs	r1, r3
	b	SavedSign

Op2Inf:
	// op2 is Infinity
	// if (expOp1 == EXP_SPECIAL)
	cmp	r4, r7
	ble	ReturnOp2	// op1 not special, return op2
SavedSign:
	add	r1, r12
	pop	{r4-r7, pc}


ENTRY_POINT	__dmul, __aeabi_dmul
	push	{r4-r7, lr}
	// compute final sign
	movs	r6, #1
	lsls	r6, #31		// sign position
	movs	r7, r3
	eors	r7, r1
	ands	r7, r6		// final sign
	mov	r12, r7

	// r1:r0 = op1
	// r3:r2 = op2
	// r6 = 0x80000000 (sign bit position)
	// r12 = result sign

	// clear signs
	bics	r1, r6
	bics	r3, r6

	ldr	r7, =#EXP_SPECIAL64 - 1
	lsrs	r4, r1, #MANT_BITS_HI64	// op1 exponent
	beq	Op1ZeroExp
Op1Normalized:
	lsrs	r5, r3, #MANT_BITS_HI64	// op2 exponent
	beq	Op2ZeroExp
Op2Normalized:
	cmp	r5, r7
	bgt	Op2SpclExp
	cmp	r4, r7
	bgt	SavedSign		// just return op1 if special

	// r1:r0 = op1
	// r3:r2 = op2
	// r4 = op1 exponent
	// r5 = op2 exponent (zero)
	// r6 = 0x80000000 (sign bit position)
	// r7 = max allowed exponent
	// r12 = result sign

	adds	r4, r5		// compute exponent

	// Clear exponent, set implied bit
	lsls	r1, #EXP_BITS64
	lsls	r3, #EXP_BITS64
	orrs	r1, r6
	orrs	r3, r6
	lsrs	r1, #EXP_BITS64
	lsrs	r3, #EXP_BITS64

	// compute 106-bit product in r1:r0:r4:r5
	push	{r0, r4}	// op1  lo and save exponent
	mul32x32 r0, r2, r0, r4, r5, r6, r7	// r4:r0 lo
	mov	lr, r0		// lowest (sticky) bits
	mul32x32 r2, r1, r2, r0, r5, r6, r7	// r0:r2 mid1

	// Use two 11-bit by 21-bit multplies for top partial product into r1:r5
	lsrs	r5, r3, #11	// upper 11 (really 10) bits
	muls	r5, r1		// 30 or 31-bit result
	lsls	r6, r3, #32 - 11
	lsrs	r6, #32 - 11	// lower 11 bits
	muls	r6, r1
	// upper product shift left by 11 bits (but leaving only 9 or 10)
	lsrs	r1, r5, #32 - 11
	lsls	r5, #11
	// combine partial products
	adds	r5, r6
	bcc	1f
	adds	r1, #1
1:
	// combine mid1 (r0:r2) with r1:r5:r4 into r1:r0:r4
	adds	r4, r2
	adcs	r0, r5
	bcc	2f
	adds	r1, #1
2:
	pop	{r2}		// restore op1 lo
	mul32x32 r2, r3, r2, r3, r5, r6, r7	// r3:r2 mid2
	adds	r4, r2
	adcs	r0, r3
	bcc	3f
	adds	r1, #1
3:
	mov	r5, lr		// get low bits back
	// full result in r1:r0:r4:r5
	pop	{r2}		// restore exponent
	// start normalization
	lsls	r3, r1, #23
	bcs	NormCy
	// we need one extra left shift
	adds	r4, r4
	adcs	r0, r0
	adcs	r1, r1
	subs	r2, #1		// adjust exponent
NormCy:
	lsl96	r4, r0, r1, 11, r3
CheckExp:
	ldr	r6, =#EXP_BIAS64
	subs	r2, r6		// remove double bias
	lsls	r6, #1		// max exponent (0x7FE)
	cmp	r2, r6
	bhs	BigExp		// too big or negative

	// r1:r0 = result mantissa
	// r2 = exponent - 1
	// r4 = round & sticky bits
	// r5 = more sticky bits
	// r12 = sign bit
	lsls	r4, #1		// extract rounding bit to CY
	bcc	NoRound
	orrs	r4, r5		// any sticky bits?
	bne	RoundUp
	// round even
	lsrs	r3, r0, #1	// LSB to CY
	bcc	NoRound
RoundUp:
	adds	r0, #1
	bcc	NoRound
	adds	r1, #1
NoRound:
	lsls	r2, #MANT_BITS_HI64
	adds	r1, r2
SetSign:
	add	r1, r12
	pop	{r4-r7, pc}

BigExp:
	// r1:r0 = result mantissa
	// r2 = result exponent
	// r4 = round & sticky bits
	// r5 = more sticky bits
	// r12 = sign bit
	bge	RetInfinity
.ifdef NO_DENORMALS
	// See if it could round up
	adds	r6, r2, #1	// was exponent -1?
	bne	ReturnZero
	adds	r0, #1		// round up LSB
	adcs	r1, r6		// r6 == 0
	lsls	r3, r1, #EXP_BITS64
	bcs	NoRound		// it rounded up
ReturnZero:
	movs	r0, #0
	movs	r1, #0
.else
	orrs	r4, r5		// combine all sticky bits
	bl	__ddenormal_result
.endif
	b	SetSign

RetInfinity:
	// return infinity
	ldr	r1, =#INFINITY64
	movs	r0, #0
	b	SetSign


	.endfunc
