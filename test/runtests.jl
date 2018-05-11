using LIBTIFF
using Base.Test

# test reading

grey_float32 = fill(Float32(0), (50, 60))
grey_float32[20:40, 10:15] = 1
grey_int = fill(Int8(0), (50, 60))
grey_int[20:40, 10:15] = -1

@test all(tiffread("test_data/grey_tile_float32.tif") .== grey_float32)
@test all(tiffread("test_data/grey_tile_float16.tif") .== Float16.(grey_float32))
@test all(tiffread("test_data/grey_tile_uint16.tif") .== UInt16.(grey_float32) * (2^16 - 1))
@test all(tiffread("test_data/grey_tile_uint32.tif") .== UInt32.(grey_float32) * (2^32 - 1))

@test all(tiffread("test_data/grey_scanline_float16.tif") .== Float16.(grey_float32))
@test all(tiffread("test_data/grey_scanline_uint8.tif") .== UInt8.(grey_float32) * 255)
@test all(tiffread("test_data/grey_scanline_int8.tif") .== grey_int)

@test all(grey_float32[30:48, 7:25] .== tiffopen("test_data/grey_tile_float32.tif") do file
        file[30:48, 7:25]
    end)

@test all(Float16.(grey_float32[17:45, 2:56]) .== tiffopen("test_data/grey_scanline_float16.tif") do file
              file[17:45, 2:56]
          end)
