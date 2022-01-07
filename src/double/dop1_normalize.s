
/*
 * dop1_normalize.s
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

	.global	__dop1_normalize

//*********************************************************************
// Normalize a denormlized number passed in r1:r0 (op1)
//
// Entry:
//	r1:r0 = op1
// Exit:
//	r1:r0 = op1 fully normalized
//	r4 = op1 exponent (< 0)
//	r5 trashed
//	all other registers preserved
//*********************************************************************

	.func	__dop1_normalize

	.thumb_func
__dop1_normalize:
	push	{r6, r7, lr}
	// see which word has first non-zero bit
	movs	r5, #MANT_BITS_HI64
	lsls	r4, r1, #1	// clear sign
	bne	DenormClz
	adds	r5, #31
	movs	r4, r0
DenormClz:
	// __clz_denormal_ext uses tailored calling convention
	// r4 = input to count leading zeros
	// r5 = max count
	// r0 - r3, r7 preserved
	// r5, r6 trashed
	bl	__clz_denormal_ext	// Get leading zeros in op1
	adds	r5, r4, #1	// shift count
	negs	r4, r4		// op1 exponent
	// 64-bit shift macro
	//.macro lsl64	lo, hi, cnt, tmp1, tmp2
	lsl64	r0, r1, r5, r6, r7
	pop	{r6, r7, pc}
