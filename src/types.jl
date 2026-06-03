using Tables 

import Tables.AbstractRow


abstract type AbstractTreeRow <: AbstractRow end 
abstract type AbstractAtomicRow <: AbstractTreeRow end
abstract type AbstractParentRow <: AbstractTreeRow end

Tables.columnnames(row::T) where T <: AbstractTreeRow = fieldnames(T) 
Tables.getcolumn(row::AbstractTreeRow, ii::Int64) = getfield(row, ii)
Tables.getcolumn(row::AbstractTreeRow, fn::Symbol) = getfield(row, fn)

#Forward Fill option on missing 
function (::Type{R})(fillfunc, row::AbstractRow, init::AbstractAtomicRow) where R<:AbstractAtomicRow 
    return R(map(fn->fillfunc(fn, row, init), fieldnames(R))...)
end

function (::Type{R})(row::AbstractRow, init::AbstractAtomicRow) where R<:AbstractAtomicRow 
    return R(forward_fill, row, init)
end


#Default options for getting ids and children 
"""
    key_field(row::AbstractTreeRow)

Gets the row's identifier field which by default is `:__id__`. If your row object has a different identifier field name 
(it usually will, because it's specified by the source table file) overload this function for that specific row type.
"""
key_field(row::AbstractTreeRow) = :__id__


"""
    child_field(row::AbstractParentRow)

Gets the row's child field which by default is `:__children__`. If your row object type has a different child field name,
overload this function for that specific type
"""
child_field(row::AbstractParentRow) = :__children__

"""
    get_key(row::AbstractTreeRow) 

Gets the key for `row` (overload `key_field(row)` to change what field the key is in)
"""
get_key(row::AbstractTreeRow) = getfield(row, key_field(row))

"""
    get_children(row::AbstractParentRow)

Gets the children for `row` (overload `child_field(row)` to change what field the children are in)
"""
get_children(row::AbstractParentRow) = getfield(row, child_field(row))

"""
    forward_fill(fn::Symbol, row::AbstractRow, init::R) where R <: AbstractAtomicRow 

Produces a converted element for fieldnbame `fn` given by `row` in the appropriate type. If `row[fn]` is `Misisng` or `Nothing`
and if the field type `fn` doesn't support it, the corresponsing field of `init` will be used (i.e. imputing by forward-fill).
If forward-fill behaviour isn't desired for a particular field, make sure it supports any missing values that could be in `row` 
(usually `Union{T, Missing}`). Other rules can replace this, for example, if the `row` type uses empty String to represent a missing value,
extend a `forward_fill` rule for that specific row type.
"""
function forward_fill(fn::Symbol, row::AbstractRow, init::R) where R <: AbstractAtomicRow 
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