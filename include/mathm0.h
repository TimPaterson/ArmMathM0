//****************************************************************************
// mathm0.h
//
// Created 4/15/2025 6:45:10 PM by Tim Paterson
//
//****************************************************************************

#pragma once


#ifdef __cplusplus
extern "C" {
#endif

// Take advantage of sinf() and cosf() computed simultaneously
extern void sincosf(float radians, float *ptrSin, float *ptrCos);

#ifdef __cplusplus
}
#endif
