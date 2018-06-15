module LIBTIFF

# package code goes here
using ColorTypes, FixedPointNumbers

import Base:
    eltype, size, getindex, summary

export
    # types
    TIFFFile,
    # functions
    tiffopen, tiffclose, tiffsize, tiffread, tiffwrite

type_map = Dict(
    (1, 8) => UInt8,
    (1, 16) => UInt16,
    (1, 32) => UInt32,
    (1, 64) => UInt64,
    (2, 8) => Int8,
    (2, 16) => Int16,
    (2, 32) => Int32,
    (2, 64) => Int64,
    (3, 16) => Float16,
    (3, 32) => Float32,
    (3, 64) => Float64)

abstract type TIFFDataFormat end

type Tile <: TIFFDataFormat end
type Scanline <: TIFFDataFormat end

struct TIFFFile{T <: TIFFDataFormat}
    filehandle::Ptr{Void}
end

# opening and closing

function tiffopen(filename::String, mode::String="r")
    fp = ccall((:TIFFOpen, "libtiff"), Ptr{Void}, (Cstring, Cstring), filename, mode)
    if tiffistiled(fp)
        tiff = TIFFFile{Tile}(fp)
    else
        tiff = TIFFFile{Scanline}(fp)
    end
    return tiff
end

function tiffopen(f::Function, args...)
    file = tiffopen(args...)
    try
        f(file)
    finally
        tiffclose(file)
    end
end

function tiffclose(tifffile::TIFFFile)
    ccall((:TIFFClose, "libtiff"), Cint, (Ptr{Void},), tifffile.filehandle)
end

# helper functions

function tiffgetfield!(value, tag, file::TIFFFile)
    err = ccall((:TIFFGetField, "libtiff"), Cint, (Ptr{Void}, Clong, Ptr{Void}), file.filehandle, tag, value)
    return err
end

function tiffsetfield(value, tag, file::TIFFFile, ::Type{T}) where {T}
    v = convert(T, value)
    err = ccall((:TIFFSetField, "libtiff"), Cint, (Ptr{Void}, Clong, T), file.filehandle, tag, v)
    return err
end

function tiffistiled(fp::Ptr{Void})
    is_tiled = ccall((:TIFFIsTiled, "libtiff"), Cint, (Ptr{Void},), fp)
    return Bool(is_tiled)
end

function tiffsize(filename::String)
    shape = tiffopen(filename) do file
        tiffsize(file)
    end
    return shape
end

function tiffsize(file::TIFFFile)
    tmp_length = Array{UInt32}(1)
    tmp_width = Array{UInt32}(1)
    tiffgetfield!(tmp_length, 257, file)
    tiffgetfield!(tmp_width, 256, file)
    shape = Int[Int(tmp_length[1]), Int(tmp_width[1])]
    return shape
end

size(file::TIFFFile) = tiffsize(file)

function tifftilesize(file::TIFFFile{Tile})
    length = Array{UInt32}(1)
    width = Array{UInt32}(1)
    tiffgetfield!(length, 323, file)
    tiffgetfield!(width, 322, file)
    tiles = Int[Int(length[1]), Int(width[1])]
    return tiles
end

function tifftilesize(filename::String)
    ts = tiffopen(filename) do file
        tifftilesize(file)
    end
    return ts
end

function sample_format(file::TIFFFile)
    sf = fill(UInt16(1), 1)
    tiffgetfield!(sf, 339, file)
    return Int(sf[1])
end

function sample_format(filename::String)
    sf = tiffopen(filename) do file
        sample_format(file)
    end
    return sf
end

function n_bits(file::TIFFFile)
    sf = fill(UInt16(0), 1)
    tiffgetfield!(sf, 258, file)
    return Int(sf[1])
end

function n_bits(filename::String)
    sf = tiffopen(filename) do file
        n_bits(file)
    end
    return sf
end

function tiffdtype(filename::String)
    dt = tiffopen(filename) do file
        tiffdtype(file)
    end
    return dt
end

function tiffdtype(file::TIFFFile)
    sampleformat = sample_format(file)
    nbits = n_bits(file)
    try
        dt = type_map[sampleformat, nbits]
        return dt
    catch
        println(sampleformat, nbits)
    end
    return NaN
end

eltype(file::TIFFFile) = tiffdtype(file)

function samples_per_pixel(file::TIFFFile)
    nsamples = Array{Int16}(1)
    err = tiffgetfield!(nsamples, 277, file)
    if err != 1
        nsamples[1] = 1
    end

    return Int(nsamples[1])
end

function summary{T}(file::TIFFFile{T})
    s = size(file)
    str = "$(s[1])x$(s[2]) TIFFFile{$T}"
    return str
end

# reading
# tiled tiffs

function read_tile(yrange, xrange, file::TIFFFile{Tile}, ::Type{Val{N}}) where {N}
    nsamples = samples_per_pixel(file)
    info = tile_info(file, yrange, xrange)
    TYPE = eltype(file)
    large = nsamples, (info["endy"] - info["starty"]) * info["tiley"], (info["endx"] - info["startx"]) * info["tilex"]
    data = Array{TYPE}(large...)

    buffer = Array{TYPE}(nsamples, info["tiley"], info["tilex"])
    for y=info["starty"]:info["tiley"]:info["endy"]
        for x=info["startx"]:info["tilex"]:info["endx"]
            ccall((:TIFFReadTile, "libtiff"), Csize_t, (Ptr{Void}, Ptr{Void}, Cint, Cint, Cint, Cint), file.filehandle, buffer, x, y, 0, 0)
            ex = x + info["tilex"]
            ey = y + info["tiley"]
            data[:, y+1:ey, x+1:ex] = permutedims(buffer, [1, 3, 2])
        end
    end

    arr_buf = data[:, yrange[1]-info["offsety"]:yrange[2]-info["offsety"] - 1, xrange[1]-info["offsetx"]:xrange[2]-info["offsetx"] - 1]
    return arr_buf
end

function read_tile(yrange, xrange, file::TIFFFile{Tile}, ::Type{Val{1}})
    info = tile_info(file, yrange, xrange)
    TYPE = eltype(file)
    large = (info["endy"] - info["starty"]) * info["tiley"], (info["endx"] - info["startx"]) * info["tilex"]
    data = Array{TYPE}(large...)

    buffer = Array{TYPE}(info["tiley"], info["tilex"])
    for y=info["starty"]:info["tiley"]:info["endy"]
        for x=info["startx"]:info["tilex"]:info["endx"]
            ccall((:TIFFReadTile, "libtiff"), Csize_t, (Ptr{Void}, Ptr{Void}, Cint, Cint, Cint, Cint), file.filehandle, buffer, x, y, 0, 0)
            ex = x + info["tilex"]
            ey = y + info["tiley"]
            data[y+1:ey, x+1:ex] = buffer'
        end
    end

    arr_buf = data[yrange[1]-info["offsety"]:yrange[2]-info["offsety"] - 1, xrange[1]-info["offsetx"]:xrange[2]-info["offsetx"] - 1]
    return arr_buf
end

function tile_info(file::TIFFFile{Tile}, yrange, xrange)
    tiles = tifftilesize(file)
    startx = xrange[1] ÷ tiles[2]
    starty = yrange[1] ÷ tiles[1]
    endx = xrange[2]
    endy = yrange[2]
    offsetx = startx * tiles[2] - 1
    offsety = starty * tiles[1] - 1
    info = Dict("tilex" => tiles[2], "tiley" => tiles[1],
                "startx" => startx, "starty" => starty,
                "endx" => endx, "endy" => endy,
                "offsetx" => offsetx, "offsety" => offsety)
    return info
end


function tiffread(file::TIFFFile{Tile}, indices::Vararg{Union{UnitRange{Int}, Int}, 2})
    nsamples = samples_per_pixel(file)
    s = size(file)
    yrange = first(indices[1]) - 1, last(indices[1])
    xrange = first(indices[2]) - 1, last(indices[2])
    if yrange[2] > s[1] || xrange[2] > s[2]
        throw(BoundsError(file, indices))#"$(s[1])x$(s[2]) TIFFFile at index [$(indices[1]), $(indices[2])]"))
    end
    return read_tile(yrange, xrange, file, Val{nsamples})
end

function tiffread(file::TIFFFile{Tile})
    s = size(file)
    return tiffread(file, 1:s[1], 1:s[2])
end

# scanline tiffs
function read_scanline!(data::Array{T}, file::TIFFFile{Scanline}) where {T}
    buffer = Array{T}(size(data, 2))
    for row = 1:size(data, 1)
        ccall((:TIFFReadScanline, "libtiff"), Cint, (Ptr{Void}, Ptr{Void}, Cint, Cint), file.filehandle, buffer, row-1, 0)
        data[row, :] = buffer
    end
    return nothing
end

function read_rgba_scanline(file::TIFFFile{Scanline})
    shape = size(file)
    buffer = Array{UInt32}(shape[2], shape[1]) # transposed because libtiff saves row major
    ccall((:TIFFReadRGBAImageOriented, "libtiff"), Cint, (Ptr{Void}, Clong, Clong, Ptr{Void}, Cshort, Cint), file.filehandle, shape[2], shape[1], buffer, 1, 0)
    buffer = buffer'
    n0f8_data = unsafe_wrap(Array, Ptr{UInt8}(pointer(buffer)), (4, shape[1], shape[2]))
    return n0f8_data
end

function tiffread(file::TIFFFile{Scanline})
    TYPE = eltype(file)
    nsamples = samples_per_pixel(file)
    if nsamples > 1
        return read_rgba_scanline(file)
    else
        data = Array{TYPE}(size(file)...)
        read_scanline!(data, file)
        return data
    end
end

# writing

function defaultstripsize(columns, file)
    stripsize = ccall((:TIFFDefaultStripSize, "libtiff"), Cint, (Ptr{Void}, Cint), file.filehandle, columns)
    return stripsize
end

sampleformat(::Type(Unsigned)) = 1
sampleformat(::Type(Integer)) = 2
sampleformat(::Type(AbstractFloat)) = 3
sampleformat(x) = 4

function tiffwrite(file::TIFFFile, data; compression=1, planarconfig=1, photometric=1)
    tiffsetfield(1, 274, file, Int16) # image orientation
    tiffsetfield(1, 277, file, Int16) # samples_per_pixel
    bitspersample = length(bits(one(eltype(data))))
    tiffsetfield(bitspersample, 258, file, Int16) # bits per sample
    tiffsetfield(size(data, 2), 256, file, Int64) # image width
    tiffsetfield(size(data, 1), 257, file, Int64) # image length
    sf = sampleformat(one(eltype(data)))
    tiffsetfield(sf, 339, file, Int16) # sample format
    tiffsetfield(compression, 259, file, Int16) # compression
    tiffsetfield(photometric, 262, file, Int16) # photometric
    tiffsetfield(planarconfig, 284, file, Int16) # planar config

    stripsize = defaultstripsize(size(data, 2), file)
    tiffsetfield(stripsize, 278, file, Int64)
    # write scanline
    for i=1:size(data, 1)
        row = data[i, :]
        ccall((:TIFFWriteScanline, "libtiff"), Cint, (Ptr{Void}, Ptr{Void}, Cuint, Cushort), file.filehandle, row, i-1, 0)
    end
    ccall((:TIFFWriteDirectory, "libtiff"), Cint, (Ptr{Void},), file.filehandle)
    return
end

function tiffwrite(filename::String, data)
    tiffopen(filename, "w") do file
        tiffwrite(file, data)
    end
end

# general interface for reading
function tiffread(filename::String, indices::Vararg{Union{UnitRange{Int}, Int}, 2})
    arr = tiffopen(filename) do file
        tiffread(file, indices...)
    end
    return arr
end

function tiffread(filename::String)
    arr = tiffopen(filename) do file
        tiffread(file)
    end
    return arr
end

function tiffread(file::TIFFFile, indices::Vararg{Union{UnitRange{Int}, Int}, 2})
    data = tiffread(file)
    return data[indices...]
end

function getindex(file::TIFFFile, indices::Vararg{Union{UnitRange{Int}, Int}, 2})
    return tiffread(file, indices...)
end

end # module
