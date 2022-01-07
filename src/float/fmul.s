
/*
 * fmul.s
 *
 * Created: 6/23/2021 5:37:15 PM
 *  Author: Tim Paterson
 */ 

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


// 32-bit IEEE floating-point multiply
//
// Entry:
//	r0 = op1
//	r1 = op2
// Exit:
//	r0 = op1 * op2

FUNC_START	__fmul, __aeabi_fmul
	SAVE_REG r4-r6
	// compute final sign
	movs	r5, #1
	lsls	r5, #31		// sign position
	movs	r3, r1
	eors	r3, r0
	ands	r3, r5		// final sign
	mov	r12, r3

	lsls	r3, r1, #1	// clear op2 sign
	lsls	r2, r0, #1	// clear op1 sign
	lsrs	r2, #MANT_BITS32 + 1	// op1 exponent
	beq	Op1ZeroExp
Op1Normalized:
	lsrs	r3, #MANT_BITS32 + 1	// op2 exponent
	beq	Op2ZeroExp
Op2Normalized:

	// r0 = op1
	// r1 = op2
	// r2 = op1 exponent
	// r3 = op2 exponent
	// r5 = 0x80000000 (sign bit position)
	// r12 = final sign

	cmp	r3, #EXP_SPECIAL32
	beq	Op2SpclExp
	cmp	r2, #EXP_SPECIAL32
	beq	Op1SpclExp

	adds	r2, r3		// compute exponent

	// Clear exponent, set implied bit
	lsls	r0, #EXP_BITS32
	lsls	r1, #EXP_BITS32
	orrs	r0, r5
	orrs	r1, r5
	lsrs	r0, #8

	// Muliply and accumulate partial products
	// r0 = op1 right justified
	// r1 = op2 left justified
	// r2 = final exponent, double biased
	// r12 = final sign
	lsls	r5, r1, #16
	lsrs	r5, #24		// low 8 bits of op2
	muls	r5, r0		// low 32-bit product
	lsls	r3, r5, #16	// keep low 16 bits
	lsrs	r5, #16		// align to position
	// second partial product
	lsls	r4, r1, #8
	lsrs	r4, #24		// middle 8 bits of op2
	muls	r4, r0		// mid 32-bit product
	lsls	r6, r4, #24	// keep low 8 bits
	lsrs	r4, #8		// align to position
	adds	r3, r6
	adcs	r5, r4		// accumulate partial products
	// third partial product
	lsrs	r1, #24		// top 8 bits of op2
	muls	r0, r1		// top product
	adds	r0, r5		// accumulate
	bmi	1f		// is it normalized?
	lsls	r0, #1		// normalize
	subs	r2, #1		// adjust exponent
1:
	subs	r2, #EXP_BIAS32	// r2 = biasd exponent - 1
	cmp	r2, #EXP_SPECIAL32 - 1
	bhs	BigExp

	// r0 = result, left justified
	// r2 = result exponent - 1
	// r3 = sticky bits
	// r12 = final sign
	// check low bits
	lsls	r4, r0, #25	// look at everything below rounding bit
Align:
	lsrs	r0, #8		// normal alignment, rounding bit to CY
	bcc	Aligned		// if CY not set, no rounding needed
	orrs	r3, r4		// any sticky bits?
	bne	RoundUp
	lsls	r3, r0, #31	// check LSB for even
	bpl	Aligned		// if even, leave it
RoundUp:
	adds	r0, #1		// add to rounding bit
Aligned:
	lsls	r2, #MANT_BITS32
	adds	r0, r2
SetSign:
	add	r0, r12		// combine sign bit
	EXIT	r4-r6

Op2SpclExp:
	// r0 = op1
	// r1 = op2
	// r2 = op1 exponent
	// r3 = op2 exponent
	// r5 = 0x80000000 (sign bit position)
	// r12 = final sign
	//
	// mantissa == 0?
	lsls	r6, r1, #(EXP_BITS32 + 1)
	bne	ReturnOp2	// op2 is NAN, return it
	// Op2 is Infinity
	// if (expOp1 == EXP_SPECIAL)
	cmp	r2, #EXP_SPECIAL32
	beq	Op1SpclExp
ReturnOp2:
	movs	r0, r1
Op1SpclExp:
	// r0 = op1
	// r1 = op2, not special
	// r2 = op1 exponent
	// r3 = op2 exponent
	// r5 = 0x80000000 (sign bit position)
	// r12 = final sign
	bics	r0, r5		// clear existing sign
	// Return whatever op1 is, Infinity or NAN
	b	SetSign
	
BigExp:
	bge	RetInfinity
.ifdef NO_DENORMALS
	// See if it could round up
	adds	r2, #1		// was exponent -1?
	bne	ZeroResult
	lsrs	r0, #1		// make room if rounds up
	adds	r3, #0x80	// treat LSB at rounding bit
	bmi	Align
	b	ZeroResult
.else
	// r0 = result mantissa left justified
	// r2 = result exponent - 1
	// r3 = sticky bits
	// r12 = final sign
	bl	__fdenormal_result
	b	SetSign
.endif

RetInfinity:
	// Build infinity
	movs	r0, #EXP_SPECIAL32
	lsls	r0, #MANT_BITS32
	b	SetSign

.ifdef NO_DENORMALS

Op1ZeroExp:
	lsrs	r2, r3, #MANT_BITS32 + 1// op2 exponent
Op2ZeroExp:
	// zero * infinity or zero * NAN?
	cmp	r2, #EXP_SPECIAL32	// check exponent
	beq	ReturnNan
ZeroResult:
	movs	r0, #0
	b	SetSign

ReturnNan:
	ldr	r0, =#NAN32
	b	SetSign

.else

Op2ChkZero:
	// op1 is special
	lsls	r1, #1		// clear sign bit
	bne	Op1SpclExp	// not zero, return op1
ReturnNan:
	ldr	r0, =#NAN32	// 0*infinity or NAN, return NAN
	b	SetSign

Op1ChkZero:
	// op2 is special
	lsls	r0, #1		// clear sign bit
	bne	ReturnOp2	// not zero, return op2
	b	ReturnNan

Op2ZeroExp:
	// r0 = op1
	// r1 = op2
	// r2 = op1 exponent
	// r3 = op2 exponent
	// r5 = 0x80000000 (sign bit position)
	// r12 = final sign
	cmp	r2, #EXP_SPECIAL32	// check op1 exponent
	beq	Op2ChkZero
	lsls	r4, r1, #1	// clear existing sign
	beq	ZeroResult
	// op2 is denormal, so normalize it

	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r3, r7 preserved
	// r5, r6 trashed
	bl	__clz_denormal	// Get leading zeros in op2
	subs	r4, #EXP_BITS32
	negs	r3, r4		// op2 exponent
	adds	r4, #1
	lsls	r1, r4
	// restore r5
	movs	r5, #1
	lsls	r5, #31		// sign position
	b	Op2Normalized

ZeroResult:
	movs	r0, #0
	b	SetSign

Op1ZeroExp:
	// r0 = op1
	// r1 = op2
	// r2 = op1 exponent
	// r3 = op2 exponent
	// r5 = 0x80000000 (sign bit position)
	// r12 = final sign
	lsrs	r4, r3, #MANT_BITS32 + 1	// op2 exponent
	cmp	r4, #EXP_SPECIAL32
	beq	Op1ChkZero
	lsls	r4, r0, #1	// clear existing sign
	beq	ZeroResult
	// op1 is denormal, so normalize it

	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r3, r7 preserved
	// r5, r6 trashed
	bl	__clz_denormal	// Get leading zeros in op1
	subs	r4, #EXP_BITS32
	negs	r2, r4		// op1 exponent
	adds	r4, #1
	lsls	r0, r4
	// restore r5
	movs	r5, #1
	lsls	r5, #31		// sign position
	b	Op1Normalized

.endif

	.endfunc
