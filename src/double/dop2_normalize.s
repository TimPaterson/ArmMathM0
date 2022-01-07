
/*
 * dop2_normalize.s
 *
 * Created: 10/10/2021 11:03:01 AM
 *  Author: Tim
 */ 

 .syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"

	.global	__dop2_normalize

//*********************************************************************
// Normalize a denormlized number passed in r3:r2 (op2)
//
// Entry:
//	r3:r2 = op2
// Exit:
//	r3:r2 = op2 fully normalized
//	r5 = op2 exponent (< 0)
//	all other registers preserved
//*********************************************************************

	.func	__dop2_normalize

	.thumb_func
__dop2_normalize:
	push	{r4, r6, r7, lr}
	// see which word has first non-zero bit
	movs	r5, #MANT_BITS_HI64
	lsls	r4, r3, #1	// clear sign
	bne	DenormClz
	adds	r5, #31
	movs	r4, r2
DenormClz:
	// __clz_denormal_ext uses tailored calling convention
	// r4 = input to count leading zeros
	// r5 = max count
	// r0 - r3, r7 preserved
	// r5, r6 trashed
	bl	__clz_denormal_ext	// Get leading zeros in op2
	negs	r5, r4		// op2 exponent
	adds	r4, #1		// shift count
	// 64-bit shift macro
	//.macro lsl64	lo, hi, cnt, tmp1, tmp2
	lsl64	r2, r3, r4, r6, r7
	pop	{r4, r6, r7, pc}
