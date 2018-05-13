# LIBTIFF

TIFF is a widely known image file format. This package provides an interface to the libtiff library for the Julia language.

## Project State

This package is in alpha currently. It only supports reading of grayscale and RGB images. Multipages are not supported.
The goal is to provide a package that is able to handle different format types, like 16 bit Integers and tiled tiffs.

## Installation

Since this is only a wrapper for libtiff, the library needs to be installed. On most Unix systems this is already the case.
Inside julia: `Pkg.clone("git@github.com:pglock/LIBTIFF.jl.git")`

## Quickstart

Start with

```julia
using LIBTIFF
```

You can read a file directly via it's filename

```julia
# read all data
A = tiffread("test_data/grey_tile_float32.tif")

#read only a part
part = tiffread("test_data/grey_tile_float32.tif", 10:20, 30:45)
```

or open it

```julia
t = tiffopen("test_data/grey_tile_float32.tif")
s = size(t)
# eltype(t) == Float32
# t[:, :] is currently not supported
A = t[1:s[1], 1:s[2]]
part = t[10:20, 30:45]
```

