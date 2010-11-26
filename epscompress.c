/** \file epscompress.c
 *
 *  Compresses an EPS file generated from Matlab using the LZW
 *  algorithm.
 *
 *  According to most sources, the patents for LZW compression expired
 *  around 2003--2004.  If this is incorrect, please let the author know.
 *  
 *  This particular algorithm uses an unbalenced binary search tree to
 *  determine if a string exists in the dictionary.
 *
 *  Version 0.2 10-Sep-2010
 *
 *  See the license at the bottom of the file.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mex.h"

/* Maximum table size, 2^MaxBits */
#define TABLESIZE 4096
/* Number of branches for each node */
#define TABLEDEPTH 3
/* Locations of each tree branch */
#define CHILD 0
#define LEFT 1
#define RIGHT 2
/* Max/Min output bit sizes. */
#define BITMAX 12
#define BITMIN 9
/* Special input/output values. */
#define CLEARTABLE 256
#define ENDOFDATA 257
/* First free location in the index. */
#define FIRSTFREE 258
/* Maximum string storage space */
#define MAXSTR 1024
/* Maximum output width. */
#define OUTPUTWIDTH 75
/* Number of lines between DSC comments before compression starts */
#define DSCGRACE 10

/**
 *  Structure containing information about the current LZW
 *  compression state.
 */
typedef struct{
  /* Index and dictionary tables */
  unsigned int Index[ TABLEDEPTH ][ TABLESIZE ];
  unsigned char Dictionary[ TABLESIZE ];
  /* Current character being processed. */
  unsigned char CurrentChar;
  /* Current index (equivalent to the prefix). */
  int CurrentIndex;
  /* Next free index. */
  unsigned int NextIndex;
  /* Variable to store the maximum index for the current bitsize */
  unsigned int MaxIndex;
  /* Current output bitsize. */
  unsigned int BitSize;  
} LZW_State;

/**
 *  Structure containing information about the IO state.
 */
typedef struct{
  /* File pointers */
  FILE *fin;
  FILE *fout;
  unsigned int Storage;
  unsigned int ColumnWidth;
  int StorageIndex;
} IO_State;

/**
 *  Initialise LZW_State data structure.
 */
void LZW_State_Init( LZW_State *x )
{
  memset( x->Index, 0, sizeof( x->Index ) );
  memset( x->Dictionary, 0, sizeof( x->Dictionary ) );
  x->CurrentChar = 0;
  x->CurrentIndex = -1;
  x->NextIndex = FIRSTFREE;
  x->MaxIndex = (1<<BITMIN);
  x->BitSize = BITMIN;
}

/**
 *  Initialise IO_State data structure. File pointers
 *  (fin and fout) need to be initialised seperately.
 */
void IO_State_Init( IO_State *x )
{
  x->Storage = 0;
  x->ColumnWidth = 0;
  x->StorageIndex = 0;
}

/**
 *  Private function to format the output into at max character widths.
 */
void asciiprv_put( char x, IO_State *y )
{
  fputc( x, y->fout );
  y->ColumnWidth++;
  /* If output is full, print a newline */
  if( y->ColumnWidth == OUTPUTWIDTH )
  {
    fputc( 10, y->fout );
    y->ColumnWidth = 0;
  }
}

/**
 *  Takes a variable bit-length raw input stream, and formats it into
 *  ASCII85 format.
 */
void asciistreamout( unsigned int x, IO_State *y, LZW_State *z )
{
  int shift, ii;
  const int divisors[] = { 85*85*85*85, 85*85*85, 85*85, 85, 1 };
  
  /* Shift the new data in. */
  shift = (32-z->BitSize-y->StorageIndex);
  if( shift >= 0 ) y->Storage |= (x<<shift);
  else y->Storage |= (x>>-shift);
  
  y->StorageIndex += z->BitSize;
  
  /* If the buffer is full (i.e. 32-bits) output the 5 characters. */
  if( y->StorageIndex >= 32 )
  {
    /* Special case, 0 gets written out as z */
    if( y->Storage == 0 ) asciiprv_put( 'z', y );
    else
    {
      /* Otherwise, output the 5 characters. */
      for( ii=0; ii<5; ii++ )
      {
        asciiprv_put( (char)( ( y->Storage/divisors[ii] )%85+33 ), y );
      }
    }
    y->StorageIndex -= 32;
    /* Add any left-over bits to the storage. */
    if( y->StorageIndex == 0 ) y->Storage = 0;
    else y->Storage = (x<<(32-y->StorageIndex));
  }
}

/**
 *  Cleanup the output stream. Outputs whatever partially completed bits
 *  are present.
 */
void asciistreamout_cleanup( IO_State *y )
{
  int ii,numBytes;
  const int divisors[] = { 85*85*85*85, 85*85*85, 85*85, 85, 1 };

  /* Only output as many bytes as required, as per Adobe ASCII85 */
  numBytes = 5 - (32-y->StorageIndex)/8;
  for( ii=0; ii<numBytes; ii++ )
  {
    asciiprv_put( (char)( ( y->Storage/divisors[ii] )%85+33 ), y );
  }
    
  /* Cleanup variables, output the 'end of data' string. */
  y->StorageIndex = 0;
  y->Storage = 0;
  y->ColumnWidth = 0;
  fprintf(y->fout,"~>");
}

/**
 *  Update the Dictionary with new values, and outputs the current prefix.
 */
void NotInDictionary( unsigned int fromNode, unsigned int from, IO_State *y, LZW_State *z )
{
  int temp;
  
  /* Update the tables */
  z->Index[ fromNode ][ from ] = z->NextIndex;
  z->Dictionary[ z->NextIndex ] = z->CurrentChar;
  z->NextIndex++;

  /* Output the current index (prefix) */
  asciistreamout( z->CurrentIndex, y, z );
  /* Update to the new index (prefix) */
  z->CurrentIndex = z->CurrentChar;
  
  /* Check to see if bitsize has been exceeded. */
  if( z->NextIndex == z->MaxIndex )
  {
    if( z->BitSize == BITMAX )
    {
      asciistreamout( CLEARTABLE, y, z );
      temp = z->CurrentIndex;
      LZW_State_Init( z );
      z->CurrentIndex = temp;
    }
    else
    {
      z->BitSize++;
      z->MaxIndex = (1<<z->BitSize);
    }
  }
}

/**
 *  LZW Compression function.
 */
void LZW( char x, IO_State *y, LZW_State *z)
{
  unsigned int X;

  if( z->CurrentIndex == -1 )
  {
    z->CurrentIndex = x;
    return;
  }
  
  z->CurrentChar = x;
    
  /* Test to see if prefix exists as a child. */
  X = z->Index[ CHILD ][ z->CurrentIndex ];
  if( X==0 )
  {
    NotInDictionary( CHILD, z->CurrentIndex, y, z );
    return;
  }
    
  /* Binary tree search for current string. */
  while( 1 )
  {
    /* If we find a value in the dictionary */
    if( z->CurrentChar == z->Dictionary[ X ] )
    {
      z->CurrentIndex = X;
      break;
    }
    /* Otherwise, search through the tree */
    if( z->CurrentChar > z->Dictionary[ X ] )
    {
      if( z->Index[ RIGHT ][ X ] == 0 )
      {
        NotInDictionary( RIGHT, X, y, z );
        break;
      }
      else
      {
        X = z->Index[ RIGHT ][ X ];
      }
    }
    else
    {
      if( z->Index[ LEFT ][ X ] == 0 )
      {
        NotInDictionary( LEFT, X, y, z );
        break;
      }
      else X = z->Index[ LEFT ][ X ];
    }
  }
}

/**
 *  Main function call in a c-mex environment.
 */
void mexFunction(int nlhs,mxArray *plhs[],int nrhs,const mxArray *prhs[])
{
  const char eps_magic[] = {0xc5,0xd0,0xd3,0xc6,0};
  char str[ DSCGRACE ][ MAXSTR ];
  int comp_state = 0;
  int ii, jj;
  
  IO_State y;
  LZW_State z;
  
  IO_State_Init( &y );
  LZW_State_Init( &z );
  
  /* Sanity check the inputs */
  if( nrhs != 2 ) mexErrMsgTxt("Two input arguments required.\n");
  
  if( nlhs != 0 )  mexErrMsgTxt("Too many output arguments.\n");
 
  if ( !( mxIsChar(prhs[0]) && mxIsChar(prhs[1]) ) )
      mexErrMsgTxt("Inputs (filenames) must both be of type string.\n.");
  
  y.fin = fopen( mxArrayToString( prhs[0] ), "r" );
  if( y.fin == NULL )
      mexErrMsgTxt("Cannot open the input file for reading.\n");
  
  y.fout = fopen( mxArrayToString( prhs[1] ), "w" );
  if( y.fout == NULL )
      mexErrMsgTxt("Cannot open the output file for writing.\n");
  
  /* Read the header */
  fgets( &str[0][0], MAXSTR, y.fin );
  if( ( strncmp( &str[0][0], "%!PS-Adobe-", 11 ) && strncmp( &str[0][0], eps_magic, 4 ) ) )
  {
    fclose(y.fin);
    fclose(y.fout);
    mexErrMsgTxt("Input file is not an EPS file.\n");
  }
  fputs( &str[0][0], y.fout );
  
  comp_state = 0;
  while( !feof( y.fin ) )
  {
    str[0][0] = 0;
    fgets( &str[0][0], MAXSTR, y.fin );
    /* If compression is off */
    if( comp_state == 0 )
    {
      /* If the next line is a DSC comment, output and continue */
      if( !strncmp( &str[0][0], "%%", 2 ) ) fputs( &str[0][0], y.fout );
      
      /* Otherwise, determine if we need to start compression by scanning
         ahead. */
      else
      {
        for( ii=1; ii<DSCGRACE; ii++ )
        {
          /* If file ends while scanning-ahead, output what's left and finish */
          if( feof( y.fin ) )
          {
            for( jj=0; jj<ii; jj++ ) fputs( &str[jj][0], y.fout );
            fclose( y.fin );
            fclose( y.fout );
            return;
          }
          str[ii][0] = 0;
          fgets( &str[ii][0], MAXSTR, y.fin );
          /* If we find a comment, don't start compressing and exit. */
          if( !strncmp( &str[ii][0], "%%", 2 ) )
          {
            for( jj=0; jj<=ii; jj++ ) fputs( &str[jj][0], y.fout );
            ii = 0;
            break;
          }
        }
        /* If the loop ended without finding a comment, start compression */
        if( ii == DSCGRACE )
        {
          IO_State_Init( &y );
          LZW_State_Init( &z );
          fprintf(y.fout,"currentfile/ASCII85Decode filter/LZWDecode filter cvx exec\n");
          asciistreamout( CLEARTABLE, &y, &z );
          comp_state = 1;
          for( ii=0; ii<DSCGRACE; ii++ )
          {
            jj=0;
            while( str[ii][jj] != 0 )
            {
              LZW( str[ii][jj], &y, &z );
              jj++;
            }
          }
        }
      }
    }
    /* Otherwise, if compression is on. */
    else
    {
      /* If we find a DSC comment, turn compression off */
      if( !strncmp( &str[0][0], "%%", 2 ) )
      {
        NotInDictionary( 0, 0, &y, &z );
        asciistreamout( ENDOFDATA, &y, &z );
        asciistreamout_cleanup( &y );
        fprintf( y.fout, "\n%s", &str[0][0] );
        comp_state = 0;
      }
      /* Otherwise, keep compressing */
      else
      {
        ii=0;
        while( str[0][ ii ] != 0 )
        {
          LZW( str[0][ii], &y, &z );
          ii++;
        }
      }
    }
  }
  
  /* If we ended the file while compressing. */
  if( comp_state == 1 )
  {
    NotInDictionary( 0, 0, &y, &z );
    asciistreamout( ENDOFDATA, &y, &z );
    asciistreamout_cleanup( &y );
  }
  
  /* Close the files and exit. */
  fclose(y.fout);
  fclose(y.fin);
}

/* 
 Copyright (c) 2010, Zebb Prime
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the organisation nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL ZEBB PRIME BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/