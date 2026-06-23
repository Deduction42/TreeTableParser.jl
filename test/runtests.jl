using Revise
using TreeTableParser
using CSV
using Tables 

import TreeTableParser: key_field, child_field

#========================================================================================================
test code
========================================================================================================#
@kwdef struct MeasTableRow <: AbstractAtomicRow 
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

@kwdef struct TagRow <: AbstractAtomicRow 
    port :: String 
    units :: String 
    avg :: Float64
    min :: Float64
    max :: Float64 
    tolerance :: Float64 
    tag :: Union{String,Missing} 
end

@kwdef struct MeasRow <: AbstractParentRow 
    id :: String 
    location :: String
    type :: String 
    ports :: Vector{TagRow}
end
MeasRow(row::Tables.AbstractRow) = MeasRow(id=row.id, location=row.location, type=row.type, ports=[TagRow(row)])

using Test

@testset "TableTreeParser.jl" begin
    rawtable = CSV.File(joinpath(@__DIR__,"tree_table.csv"))
    initrow = MeasTableRow(rawtable[1])
    meastable = TreeTable{MeasRow}(rawtable)

    @test length(meastable[1].ports) == 2 
    @test length(meastable[2].ports) == 1
    @test ismissing(meastable[1].ports[end].tag)
end

nothing