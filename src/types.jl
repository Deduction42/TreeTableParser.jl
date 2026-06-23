using Tables 

import Tables: AbstractRow, AbstractRowTable, rows
import Base.Fix1
import Base.eachrow

abstract type AbstractTreeTable{R} <: AbstractRowTable{R} end
abstract type AbstractTreeRow <: AbstractRow end 
abstract type AbstractAtomicRow <: AbstractTreeRow end
abstract type AbstractParentRow <: AbstractTreeRow end

Tables.columnnames(row::T) where T <: AbstractTreeRow = fieldnames(T) 
Tables.getcolumn(row::AbstractTreeRow, ii::Int64) = getfield(row, ii)
Tables.getcolumn(row::AbstractTreeRow, fn::Symbol) = getfield(row, fn)

#Default constructor based on matching field names
function (::Type{R})(source::AbstractRow) where R <: AbstractAtomicRow
    return R(map(fn->convert_property(R, source, fn), fieldnames(R))...)
end

"""
    struct TreeTable{RT<:AbstractTreeRow} <: AbstractRowTable
        rows :: Vector{RT}
    end
An AbstractRowTable that contains rows of type TreeRows
"""
struct TreeTable{R<:AbstractTreeRow} <: AbstractTreeTable{R}
    rows :: Vector{R}
    TreeTable{R}(rows::Vector) where R<:AbstractTreeRow = new{R}(rows)
    TreeTable(rows::Vector{R}) where R<:AbstractTreeRow = new{R}(rows)
end
TreeTable{R}(ar::AbstractArray) where R = TreeTable{R}(convert(Vector{R}, ar))
TreeTable(ar::AbstractArray{R}) where R = TreeTable{R}(convert(Vector{R}, ar))
TreeTable{R}() where {R<:AbstractTreeRow} = TreeTable{R}(R[])
TreeTable{R}(tbl::TreeTable) where {R<:AbstractTreeRow} = TreeTable{R}(tbl.rows)
TreeTable(tbl::TreeTable) = tbl

function TreeTable{R}(sourcetable::AbstractRowTable) where {R<:AbstractTreeRow}
    tbl = TreeTable{R}()
    add_children!(tbl.rows, sourcetable)
    return tbl
end

Tables.isrowtable(::Type{<:TreeTable}) = true
Tables.rowaccess(::Type{<:TreeTable}) = true
Tables.rows(tbl::TreeTable) = tbl.rows
Base.getindex(tbl::TreeTable, ind::Integer) = tbl.rows[ind]
Base.push!(tbl::TreeTable, row::AbstractRow) = add_child!(tbl.rows, row)
Base.append!(tbl::TreeTable, sourcerows::AbstractRowTable) = add_children!(tbl.rows, sourcerows)

#Default options for getting ids and children 
"""
    key_field(::Type{R}) where R<:AbstractTreeRow

Gets the row's identifier field which by default is the first field name. If your row object has a different identifier field name 
overload this function for that specific row type.
"""
key_field(::Type{R}) where R<:AbstractTreeRow = first(fieldnames(R))
key_field(row::AbstractTreeRow) = key_field(typeof(row))

"""
    child_field(row::AbstractParentRow)

Gets the row's child field which by default is the last field name. If your row object type has a different child field name,
overload this function for that specific type
"""
child_field(::Type{R}) where R<:AbstractTreeRow = last(fieldnames(R))
child_field(row::AbstractTreeRow) = child_field(typeof(row))

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


function find_row(rows::AbstractVector{R}, k) where R <:AbstractTreeRow
    key = cell_convert(fieldtype(R, key_field(R)), k)
    return findfirst(r->get_key(r)==key, rows)
end
find_child(parent::AbstractParentRow, k) = find_row(get_children(parent), k)


function get_row(rows::AbstractVector{<:AbstractTreeRow}, k)
    ind = find_row(rows, k)
    isnothing(ind) && error("Key $(k) not found in $(get_key.(rows))")
    return rows[ind]
end
get_child(parent::AbstractParentRow, k) = get_row(get_children(parent), k)

"""
    is_match(newrow::RN, oldrow::RO) where {RN <: AbstractParentRow, RO <: AbstractTreeRow}

Checks the non-special fields of `newrow` to see if they match the fields of `oldrow`. If the fieldnames of `newrow` do not  
match the names and types of `oldrow`, you will need to overload this function to convert `oldrow` to the same type as `newrow`.
"""
function is_match(currentrow::R, sourcerow::AbstractRow) where {R <: AbstractParentRow}
    field_soft_match(fn::Symbol) = (fn==child_field(R)) ? true : is_soft_match(R, currentrow[fn], sourcerow[fn])

    if !field_soft_match(key_field(R)) #Different keys means they are not duplicates
        return false
    end 

    #If the keys are a soft match then all non-special rows must be soft matches of the parent
    for fn in fieldnames(R)
        field_soft_match(fn) || error("Rows with duplicate ids must have identical values for a given field. Field $(fn) contained $(sourcerow[fn] => currentrow[fn])")
    end

    return true 
end


"""
    allows_forwarding(::Type{AbstractTreeRow}) = false 

Indicate if your tree row type allows forwarding. By default pararent rows allow forwarding while atomic rows do not.
"""
allows_forwarding(::Type{<:AbstractTreeRow}) = false 
allows_forwarding(::Type{<:AbstractParentRow}) = true

function is_soft_match(::Type{R}, oldval, newval) where {R<:AbstractTreeRow}
    if allows_forwarding(R)
        return is_soft_match(oldval, newval)
    else
        return is_hard_match(oldval, newval)
    end
end
is_soft_match(oldval, newval) = is_missing_cell(newval) ? true : is_hard_match(oldval, newval)
is_hard_match(oldval, newval) = cell_convert(typeof(oldval), newval) === oldval

is_missing_cell(x::Union{Nothing,Missing}) = true 
is_missing_cell(x::AbstractString) = isempty(x)
is_missing_cell(x::Symbol) = (x==Symbol(""))
is_missing_cell(x::Real) = isnan(x)
is_missing_cell(x::Any) = false

function add_children!(siblings::AbstractVector{<:AbstractTreeRow}, sourcetable)
    for row in Tables.rows(sourcetable)
        add_child!(siblings, row)
    end
    validate_keys(siblings)
    return siblings 
end

function add_child!(siblings::AbstractVector{TR}, sourcerow::AbstractRow) where {TR<:AbstractTreeRow}
    if isempty(siblings)
        push!(siblings, TR(sourcerow))
        return nothing 
    end

    newsibling = add_child!(siblings[end], sourcerow)
    if !isnothing(newsibling) 
        push!(siblings, newsibling)
    end
    return nothing
end

function add_child!(parentrow::PR, sourcerow::AbstractRow) where {PR<:AbstractParentRow}
    if is_match(parentrow, sourcerow)
        add_child!(get_children(parentrow), sourcerow)
        return nothing
    else
        validate_keys(get_children(parentrow)) #Ensure children are unique before moving on
        return PR(sourcerow)
    end
end

function add_child!(parentrow::AR, sourcerow::AbstractRow) where {AR<:AbstractAtomicRow}
    return AR(sourcerow)
end

function validate_keys(v::AbstractVector{<:AbstractTreeRow})
    ids = (get_key(r) for r in v)
    allunique(ids) || error("ValidationError: Keys are not unique $(collect(ids))")
    return v 
end


#====================================================================================================================
# Cell conversion functions
====================================================================================================================#
convert_property(::Type{T}, source, fn::Symbol) where T = cell_convert(fieldtype(T, fn), getproperty(source, fn))

#Generic conversion rules 
cell_convert(::Type{T}, x) where T = convert(T, x)
cell_convert(::Type{Union{Nothing, T}}, x::Union{Nothing,Missing}) where T = nothing
cell_convert(::Type{Union{Missing, T}}, x::Union{Nothing,Missing}) where T = missing

#Conversion to string
cell_convert(::Type{String}, x) = string(x)
cell_convert(::Type{String}, x::AbstractString) = String(strip(x))
cell_convert(::Type{String}, x::Union{Nothing,Missing}) = "" 

#Conversion to symbols
cell_convert(::Type{Symbol}, x) = Symbol(cell_convert(String, x))

#Conversion to numbers
cell_convert(::Type{T}, x) where T<:Real = convert(T, x)
cell_convert(::Type{T}, x::AbstractString) where T<:Real = something(tryparse(T, x), convert(T, NaN))
cell_convert(::Type{T}, x::Union{Nothing,Missing}) where T<:Real = convert(T, NaN)