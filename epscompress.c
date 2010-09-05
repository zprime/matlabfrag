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
 *  Version 0.1 29-Aug-2010
 *
 *  See the license at the bottom of the file.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mex.h"

// Maximum table size, 2^MaxBits
#define TABLESIZE 4096
// Number of branches for each node
#define TABLEDEPTH 3
// Locations of each tree branch
#define CHILD 0
#define LEFT 1
#define RIGHT 2
// Max/Min output bit sizes.
#define BITMAX 12
#define BITMIN 9
// Special input/output values.
#define CLEARTABLE 256
#define ENDOFDATA 257
// First free location in the index.
#define FIRSTFREE 258
// Maximum string storage space
#define MAXSTR 1024
// Maximum output width.
#define OUTPUTWIDTH 75

/*
 *  Uncomment one of the following to determine the output format.
 *  ASCII (ASCII85) output is recommended as it is more compatible with
 *  programs such as LaTeX, even though the output is 5/4 times larger.
 */
//#define RAWOUTPUT
#define ASCIIOUTPUT
  
typedef struct{
  // Index and dictionary tables
  unsigned int Index[ TABLEDEPTH ][ TABLESIZE ];
  unsigned char Dictionary[ TABLESIZE ];
  // Current character being processed.
  unsigned char CurrentChar;
  // Current index (equivalent to the prefix).
  unsigned int CurrentIndex;
  // Next free index.
  unsigned int NextIndex;
  // Variable to store the maximum index for the current bitsize
  unsigned int MaxIndex;
  // Current output bitsize.
  unsigned int BitSize;  
} LZW_State;

typedef struct{
  // File pointers
  FILE *fin;
  FILE *fout;
  unsigned int Storage;
  unsigned int ColumnWidth;
  int StorageIndex;
} IO_State;

/**
 *  Initialise LZW_State data structure.
 */
void LZW_State_Init( LZW_State x )
{
  memset( x.Index, 0, sizeof( x.Index ) );
  memset( x.Dictionary, 0, sizeof( x.Dictionary ) );
  x.CurrentChar = 0;
  x.CurrentIndex = 0;
  x.NextIndex = FIRSTFREE;
  x.MaxIndex = (1<<BITMIN);
  x.BitSize = BITMIN;
}

/**
 *  Initialise IO_State data structure.
 */
void IO_State_Init( IO_State x )
{
  x.Storage = 0;
  x.ColumnWidth = 0;
  x.StorageIndex = 0;
}

/**
 *  Write out a variable bit-length raw bitstream.
 *  Hopefully endian-independent.
 */
void rawstreamout( unsigned int x, IO_State y, LZW_State z )
{ 
  // Add the bits to the storage variable
  y.Storage |= x<<(32-z.BitSize-y.StorageIndex);
  y.StorageIndex += z.BitSize;
  
  // Output all complete characters.
  while( y.StorageIndex >= 8 )
  {
    fputc( (char)(y.Storage>>24), y.fout );
    y.StorageIndex -= 8;
    y.Storage <<= 8;
  }
}

/**
 *  Cleanup streamout.  Outputs whatever incomplete characters are present.
 */
void rawstreamout_cleanup( IO_State y )
{
  if( y.Storage ) fputc( (char)(y.Storage>>24), y.fout );
  y.StorageIndex = 0;
  y.Storage = 0;
}

/**
 *  Private function to format the output into at max character widths.
 */
void asciiprv_put( char x, IO_State y )
{
  fputc( x, y.fout );
  y.ColumnWidth++;
  // If output is full, print a newline
  if( y.ColumnWidth == OUTPUTWIDTH )
  {
    fputc( 10, y.fout );
    y.ColumnWidth = 0;
  }
}

/**
 *  Takes a variable bit-length raw input stream, and formats it into
 *  ASCII85 format.
 */
void asciistreamout( unsigned int x, IO_State y, LZW_State z )
{
  int shift;
  // Shift the new data in.
  shift = (32-z.BitSize-y.StorageIndex);
  if( shift >= 0 ) y.Storage |= (x<<shift);
  else y.Storage |= (x>>-shift);
  
  y.StorageIndex += z.BitSize;
  
  // If the buffer is full (i.e. 32-bits) output the 5 characters.
  if( y.StorageIndex >= 32 )
  {
    // Special case, 0 gets written out as z
    if( y.Storage == 0 ) asciiprv_put( 'z', y );
    else
    {
      // Otherwise, output the 5 characters.
      asciiprv_put( (char)((y.Storage/85/85/85/85)%85+33), y );
      asciiprv_put( (char)((y.Storage/85/85/85)%85+33), y );
      asciiprv_put( (char)((y.Storage/85/85)%85+33), y );
      asciiprv_put( (char)((y.Storage/85)%85+33), y );
      asciiprv_put( (char)((y.Storage)%85+33), y );
    }
    y.StorageIndex -= 32;
    // Add any left-over bits to the storage.
    if( y.StorageIndex == 0 ) y.Storage = 0;
    else y.Storage = (x<<(32-y.StorageIndex));
  }
}

/**
 *  Cleanup the output stream. Outputs whatever partially completed bits
 *  are present.
 */
void asciistreamout_cleanup( IO_State y )
{
  // Special case, 0 gets written as z
  if( y.Storage == 0 ) asciiprv_put( 'z', y );
  else
  {
    // Otherwise, output the 5 characters.
    asciiprv_put( (char)((y.Storage/85/85/85/85)%85+33), y );
    asciiprv_put( (char)((y.Storage/85/85/85)%85+33), y );
    asciiprv_put( (char)((y.Storage/85/85)%85+33), y );
    asciiprv_put( (char)((y.Storage/85)%85+33), y );
    asciiprv_put( (char)((y.Storage)%85+33), y );
  }
  // Cleanup variables, output the 'end of data' string.
  y.StorageIndex = 0;
  y.Storage = 0;
  y.ColumnWidth = 0;
  fprintf(y.fout,"~>");
}

/**
 *  Update the Dictionary with new values, and outputs the current prefix.
 */
void NotInDictionary( unsigned int fromNode, unsigned int from, IO_State y, LZW_State z )
{
  // Update the tables
  z.Index[ fromNode ][ from ] = z.NextIndex;
  z.Dictionary[ z.NextIndex ] = z.CurrentChar;
  z.NextIndex++;

  // Output the current index (prefix)
  asciistreamout( z.CurrentIndex, y, z );
  // Update to the new index (prefix)
  z.CurrentIndex = z.CurrentChar;
  
  // Check to see if bitsize has been exceeded.
  if( z.NextIndex == z.MaxIndex )
  {
    if( z.BitSize == BITMAX )
    {
      asciistreamout( CLEARTABLE, y, z );
      LZW_State_Init( z );
    }
    else
    {
      z.BitSize++;
      z.MaxIndex = (1<<z.BitSize);
    }
  }
}

/**
 *  Main function call in a c-mex environment.
 */
void mexFunction(int nlhs,mxArray *plhs[],int nrhs,const mxArray *prhs[])
{
  unsigned int X;
  char str[ MAXSTR ];
  
  IO_State y;
  LZW_State z;
  
  IO_State_Init( y );
  LZW_State_Init( z );
  
  // Sanity check the inputs
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
  
  // Scan input file until the end of the header is found.
  while( !feof( y.fin ) )
  {
    fgets( str, MAXSTR, y.fin );
    fputs( str, y.fout );
    if( !strncmp(str,"%%EndComments",10) )
    {
      break;
    }
  }
  if( feof( y.fin ) )
  {
    fclose(y.fin);
    fclose(y.fout);
    mexErrMsgTxt("Unexpected end of file.\n");
  }
  
#ifdef RAWOUTPUT
  fprintf(y.fout,"\ncurrentfile/LZWDecode filter cvx exec\n");
#endif
#ifdef ASCIIOUTPUT
  fprintf(y.fout,"\ncurrentfile/ASCII85Decode filter/LZWDecode filter cvx exec\n");
#endif
  
  z.CurrentIndex = fgetc( y.fin );
  
  asciistreamout( CLEARTABLE, y, z );
  
  // Loop through all of the input data.
  while( !feof( y.fin ) )
  {
    z.CurrentChar = fgetc( y.fin );
    
    // Test to see if prefix exists as a child.
    X = z.Index[ CHILD ][ z.CurrentIndex ];
    if( X==0 )
    {
      NotInDictionary( CHILD, z.CurrentIndex, y, z );
      continue;
    }
    
    // Binary tree search for current string.
    while( 1 )
    {
      // If we find a value in the dictionary
      if( z.CurrentChar == z.Dictionary[ X ] )
      {
        z.CurrentIndex = X;
        break;
      }
      // Otherwise, search through the tree
      if( z.CurrentChar > z.Dictionary[ X ] )
      {
        if( z.Index[ RIGHT ][ X ] == 0 )
        {
          NotInDictionary( RIGHT, X, y, z );
          break;
        }
        else X = z.Index[ RIGHT ][ X ];
      }
      else
      {
        if( z.Index[ LEFT ][ X ] == 0 )
        {
          NotInDictionary( LEFT, X, y, z );
          break;
        }
        else X = z.Index[ LEFT ][ X ];
      }
    }
  }
  
  // Clean up the output.
  asciistreamout( ENDOFDATA, y, z );
  asciistreamout_cleanup( y );
  
  fclose(y.fout);
  fclose(y.fin);
}

// Copyright (c) 2010, Zebb Prime
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the organisation nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL ZEBB PRIME BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.