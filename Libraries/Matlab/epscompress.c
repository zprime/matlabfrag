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

/*
 *  Uncomment one of the following to determine the output format.
 *  ASCII (ASCII85) output is recommended as it is more compatible with
 *  programs such as LaTeX, even though the output is 5/4 times larger.
 */
//#define RAWOUTPUT
#define ASCIIOUTPUT

// File pointers
FILE *fin = NULL;
FILE *fout = NULL;

// Index and dictionary tables
unsigned int Index[ TABLEDEPTH ][ TABLESIZE ];
unsigned char Dictionary[ TABLESIZE ];
// Current character being processed.
unsigned char CurChar;
// Current index (equivalent to the prefix).
unsigned int CurInd;
// Next free index.
unsigned int NextInd;
// Variable to store the maximum index for the current bitsize
unsigned int MaxInd;
// Current output bitsize.
unsigned int BitSize;

int Streamout_Ind = 0;

#ifdef RAWOUTPUT
#undef ASCIIOUTPUT

unsigned int Streamout_Storage = 0;

/**
 *  Write out a variable bit-length raw bitstream.
 *  Hopefully endian-independent.
 */
void streamout( unsigned int x )
{ 
  // Add the bits to the storage variable
  Streamout_Storage |= x<<(32-BitSize-Streamout_Ind);
  Streamout_Ind += BitSize;
  
  // Output all complete characters.
  while( Streamout_Ind >= 8 )
  {
    fputc( (char)(Streamout_Storage>>24), fout );
    Streamout_Ind -= 8;
    Streamout_Storage <<= 8;
  }
}

/**
 *  Cleanup streamout.  Outputs whatever incomplete characters are present.
 */
void streamout_cleanup( void )
{
  if( Streamout_Storage ) fputc( (char)(Streamout_Storage>>24), fout );
  Streamout_Ind = 0;
  Streamout_Storage = 0;
}
#endif /* ifdef RAWOUTPUT */


#ifdef ASCIIOUTPUT

unsigned int Streamout_Storage = 0;
// Maximum output width.
#define OUTPUTWIDTH 75
unsigned int Streamout_Width = 0;

/**
 *  Private function to format the output into at max character widths.
 */
void prv_put( char x )
{
  fputc( x, fout );
  Streamout_Width++;
  // If output is full, print a newline
  if( Streamout_Width == OUTPUTWIDTH )
  {
    fputc( 10, fout );
    Streamout_Width = 0;
  }
}

/**
 *  Takes a variable bit-length raw input stream, and formats it into
 *  ASCII85 format.
 */
void streamout( unsigned int x )
{
  int shift;
  // Shift the new data in.
  shift = (32-BitSize-Streamout_Ind);
  if( shift >= 0 ) Streamout_Storage |= (x<<shift);
  else Streamout_Storage |= (x>>-shift);
  
  Streamout_Ind += BitSize;
  
  // If the buffer is full (i.e. 32-bits) output the 5 characters.
  if( Streamout_Ind >= 32 )
  {
    // Special case, 0 gets written out as z
    if( Streamout_Storage == 0 ) prv_put( 'z' );
    else
    {
      // Otherwise, output the 5 characters.
      prv_put( (char)((Streamout_Storage/85/85/85/85)%85+33) );
      prv_put( (char)((Streamout_Storage/85/85/85)%85+33) );
      prv_put( (char)((Streamout_Storage/85/85)%85+33) );
      prv_put( (char)((Streamout_Storage/85)%85+33) );
      prv_put( (char)((Streamout_Storage)%85+33) );
    }
    Streamout_Ind -= 32;
    // Add any left-over bits to the storage.
    if( Streamout_Ind == 0 ) Streamout_Storage = 0;
    else Streamout_Storage = (x<<(32-Streamout_Ind));
  }
}

/**
 *  Cleanup the output stream. Outputs whatever partially completed bits
 *  are present.
 */
void streamout_cleanup( void )
{
  // Special case, 0 gets written as z
  if( Streamout_Storage == 0 ) prv_put( 'z' );
  else
  {
    // Otherwise, output the 5 characters.
    prv_put( (char)((Streamout_Storage/85/85/85/85)%85+33) );
    prv_put( (char)((Streamout_Storage/85/85/85)%85+33) );
    prv_put( (char)((Streamout_Storage/85/85)%85+33) );
    prv_put( (char)((Streamout_Storage/85)%85+33) );
    prv_put( (char)((Streamout_Storage)%85+33) );
  }
  // Cleanup variables, output the 'end of data' string.
  Streamout_Ind = 0;
  Streamout_Storage = 0;
  Streamout_Width = 0;
  fprintf(fout,"~>");
}
#endif /* ifdef ASCIIOUTPUT */

/**
 *  Initialise the Index and Dictionary, and output the special
 *  ClearTable character.
 */
void tableInit( void )
{
  unsigned int temp1,temp2;
  
  streamout( CLEARTABLE );
  
  memset( Dictionary, 0, sizeof( Dictionary ) );
  memset( Index, 0, sizeof( Index ) );
  
  BitSize = BITMIN;
  MaxInd = (1<<BitSize);
  NextInd = FIRSTFREE;
}

/**
 *  Update the Dictionary with new values, and outputs the current prefix.
 */
void NotInDictionary( unsigned int fromNode, unsigned int from )
{
  // Update the tables
  Index[ fromNode ][ from ] = NextInd;
  Dictionary[ NextInd ] = CurChar;
  NextInd++;

  // Output the current index (prefix)
  streamout( CurInd );
  // Update to the new index (prefix)
  CurInd = CurChar;
  
  // Check to see if bitsize has been exceeded.
  if( NextInd == MaxInd )
  {
    if( BitSize == BITMAX ) tableInit();
    else
    {
      BitSize++;
      MaxInd = (1<<BitSize);
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
  
  Streamout_Ind = 0;
  Streamout_Storage = 0;
  BitSize = BITMIN;
  
  // Sanity check the inputs
  if( nrhs != 2 ) mexErrMsgTxt("Two input arguments required.\n");
  
  if( nlhs != 0 )  mexErrMsgTxt("Too many output arguments.\n");
 
  if ( !( mxIsChar(prhs[0]) && mxIsChar(prhs[1]) ) )
      mexErrMsgTxt("Inputs (filenames) must both be of type string.\n.");
  
  fin = fopen( mxArrayToString( prhs[0] ), "r" );
  if( fin == NULL )
      mexErrMsgTxt("Cannot open the input file for reading.\n");
  
  fout = fopen( mxArrayToString( prhs[1] ), "w" );
  if( fout == NULL )
      mexErrMsgTxt("Cannot open the output file for writing.\n");
  
  if( feof( fin ) )
  {
    fclose(fin);
    fclose(fout);
    mexErrMsgTxt("Input file is empty.\n");
  }
  
  // Scan input file until the end of the header is found.
  while( !feof( fin ) )
  {
    fgets( str, MAXSTR, fin );
    fputs( str, fout );
    if( !strncmp(str,"%%EndComments",10) )
    {
      break;
    }
  }
  if( feof( fin ) )
  {
    fclose(fin);
    fclose(fout);
    mexErrMsgTxt("Unexpected end of file.\n");
  }
  
#ifdef RAWOUTPUT
  fprintf(fout,"\ncurrentfile/LZWDecode filter cvx exec\n");
#endif
#ifdef ASCIIOUTPUT
  fprintf(fout,"\ncurrentfile/ASCII85Decode filter/LZWDecode filter cvx exec\n");
#endif
  
  CurInd = fgetc( fin );
  
  tableInit();
  
  // Loop through all of the input data.
  while( !feof( fin ) )
  {
    CurChar = fgetc( fin );
    
    // Test to see if prefix exists as a child.
    X = Index[ CHILD ][ CurInd ];
    if( X==0 )
    {
      NotInDictionary( CHILD, CurInd );
      continue;
    }
    
    // Binary tree search for current string.
    while( 1 )
    {
      // If we find a value in the dictionary
      if( CurChar == Dictionary[ X ] )
      {
        CurInd = X;
        break;
      }
      // Otherwise, search through the tree
      if( CurChar > Dictionary[ X ] )
      {
        if( Index[ RIGHT ][ X ] == 0 )
        {
          NotInDictionary( RIGHT, X );
          break;
        }
        else X = Index[ RIGHT ][ X ];
      }
      else
      {
        if( Index[ LEFT ][ X ] == 0 )
        {
          NotInDictionary( LEFT, X );
          break;
        }
        else X = Index[ LEFT ][ X ];
      }
    }
  }
  
  // Clean up the output.
  streamout( ENDOFDATA );
  streamout_cleanup();
  
  fclose(fout);
  fclose(fin);
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