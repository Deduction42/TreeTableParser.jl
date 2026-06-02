using Tables 

import Tables.AbstractRow


abstract type AbstractTreeRow <: AbstractRow end 
abstract type AbstractAtomicRow <: AbstractTreeRow end
abstract type AbstractParentRow <: AbstractTreeRow end

Tables.columnnames(row::T) where T <: AbstractTreeRow = fieldnames(T) 
Tables.getcolumn(row::AbstractTreeRow, ii::Int64) = getfield(row, ii)
Tables.getcolumn(row::AbstractTreeRow, fn::Symbol) = getfield(row, fn)

#Forward Fill option on missing 
function (::Type{R})(mergefunc, row::AbstractRow, init::AbstractAtomicRow) where R<:AbstractAtomicRow 
    return R(map(fn->mergefunc(fn, row, init), fieldnames(R))...)
end

function (::Type{R})(row::AbstractRow, init::AbstractAtomicRow) where R<:AbstractAtomicRow 
    return R(default_merger, row, init)
end


function default_merger(fn::Symbol, row::AbstractRow, init::R) where R <: AbstractAtomicRow 
    rowval = row[fn]
    try 
        return convert(fieldtype(R, fn), rowval)
    catch
        (rowval isa Union{Nothing, Missing}) && return init[fn]
    end
    throw(ArgumentError("Row value '$(rowval)' is incompaatible with field :$(fn) (which has type $(fieldtype(R, fn)))"))
end


#========================================================================================================
test code
========================================================================================================#
import Base.Fix1
using CSV 
table = CSV.File(joinpath(@__DIR__,"tree_table.csv"))


struct RawMeasRow <: AbstractAtomicRow 
    id :: String 
    location :: String 
    type :: String 
    port :: String 
    units :: String 
    avg :: Float64 
    min :: Float64 
    max :: Float64 
    tolerance :: Float64 
    tag :: Union{String,Missing} 
end

function RawMeasRow(row::Tables.AbstractRow)
    return RawMeasRow( map(Fix1(getproperty, row), fieldnames(RawMeasRow))... )
end

row1 = RawMeasRow(table[1])
row2 = RawMeasRow(table[2], row1)
row3 = RawMeasRow(table[3], row2)