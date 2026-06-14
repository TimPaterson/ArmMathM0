//****************************************************************************
// logtablef.s
//
// Created 5/23/2026 6:11:11 PM by Tim Paterson
//
//****************************************************************************

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"


	.global	__logtablef

//****************************************************************************
// Table of natural logarithms for 1 + 2^-n, 1 <= n <= 16, p32
//****************************************************************************

__logtablef:
	.word	0x67CC8FB3	// ln(1 + 2^-1)
	.word	0x391FEF8F	// ln(1 + 2^-2)
	.word	0x1E27076E	// ln(1 + 2^-3)
	.word	0x0F851860	// ln(1 + 2^-4)
	.word	0x07E0A6C4	// ln(1 + 2^-5)
	.word	0x03F81516	// ln(1 + 2^-6)
	.word	0x01FE02A7	// ln(1 + 2^-7)
	.word	0x00FF8055	// ln(1 + 2^-8)
	.word	0x007FE00B	// ln(1 + 2^-9)
	.word	0x003FF801	// ln(1 + 2^-10)
	.word	0x001FFE00	// ln(1 + 2^-11)
	.word	0x000FFF80	// ln(1 + 2^-12)
	.word	0x0007FFE0	// ln(1 + 2^-13)
	.word	0x0003FFF8	// ln(1 + 2^-14)
	.word	0x0001FFFE	// ln(1 + 2^-15)
	.word	0x00010000	// ln(1 + 2^-16)
