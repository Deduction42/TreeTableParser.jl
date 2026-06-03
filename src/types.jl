using Tables 

import Tables: AbstractRow, AbstractRowTable, rows
import Base.Fix1
import Base.eachrow

abstract type AbstractTreeRow <: AbstractRow end 
abstract type AbstractAtomicRow <: AbstractTreeRow end
abstract type AbstractParentRow <: AbstractTreeRow end

Tables.columnnames(row::T) where T <: AbstractTreeRow = fieldnames(T) 
Tables.getcolumn(row::AbstractTreeRow, ii::Int64) = getfield(row, ii)
Tables.getcolumn(row::AbstractTreeRow, fn::Symbol) = getfield(row, fn)

#Default construction
function (::Type{R})(row::AbstractRow) where R <: AbstractAtomicRow
    return R(map(Fix1(getproperty, row), fieldnames(R))...)
end

#Forward Fill option on missing 
function (::Type{R})(fillfunc, row::AbstractRow, init::AbstractAtomicRow) where R<:AbstractAtomicRow 
    return R(map(fn->fillfunc(fn, row, init), fieldnames(R))...)
end

function (::Type{R})(row::AbstractRow, init::AbstractAtomicRow) where R<:AbstractAtomicRow 
    return R(forward_fill, row, init)
end

"""
    collapse(::Type{RT}, initrow::AbstractTreeRow, table::AbstractRowTable)

Create a collapsed version of `table`, with row type `RT` that is constructed by source type `ST`
"""
function collapse(::Type{RT}, initrow::AbstractTreeRow, table::AbstractRowTable) where {RT<:AbstractTreeRow}
    sourcerow = Ref(initrow)
    tablerows = [RT(initrow)]
    
    for (ii, row) in enumerate(Tables.rows(table))
        ii == 1 && continue
        sourcerow[] = forward_fill(row, sourcerow[])
        add_child!(tablerows, sourcerow[])
    end

    return tablerows
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

function forward_fill(row::AbstractRow, init::RT) where RT <: AbstractAtomicRow
    return RT( map(fn->forward_fill(fn, row, init), fieldnames(RT))... )
end

"""
    is_duplicate(newrow::RN, oldrow::RO) where {RN <: AbstractParentRow, RO <: AbstractTreeRow}

Checks the non-special fields of `newrow` to see if they match the fields of `oldrow`. If the fieldnames of `newrow` do not  
match the names and types of `oldrow`, you will need to overload this function to convert `oldrow` to the same type as `newrow`.
"""
function isduplicate(newrow::RN, oldrow::RO) where {RN <: AbstractParentRow, RO <: AbstractTreeRow}
    special_field(fn::Symbol) = (fn==key_field(newrow))|(fn==child_field(newrow))
    compatible_vals(fn::Symbol) = special_field(fn) ? true : newrow[fn] == oldrow[fn]

    if get_key(newrow) != get_key(oldrow) #Different keys means they are not duplicate
        return false
    end 

    #If the keys are the same, then all non-special rows must be identical 
    for fn in fieldnames(RN)
        compatible_vals(fn) || error("Rows with duplicate ids must have identical values for a given field. Field $(fn) contained $(oldrow[fn] => newrow[fn])")
    end

    return true 
end

function add_child!(parentrow::PR, sourcerow::AbstractAtomicRow) where {PR<:AbstractParentRow}
    if isduplicate(parentrow, sourcerow)
        add_child!(get_children(parentrow), sourcerow)
        return nothing
    else
        return PR(sourcerow)
    end
end

function add_child!(parentrow::AR, sourcerow::AbstractAtomicRow) where {AR<:AbstractAtomicRow}
    return AR(sourcerow)
end

function add_child!(siblings::AbstractVector{<:AbstractTreeRow}, sourcerow::AbstractAtomicRow)
    newsibling = add_child!(siblings[end], sourcerow)

    isnothing(newsibling) && return nothing
    push!(siblings, newsibling)

    return nothing
end

