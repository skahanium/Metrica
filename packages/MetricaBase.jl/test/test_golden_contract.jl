using Test
include("golden_test_helpers.jl")

@testset "Golden JSON schema contract" begin
    ids = list_golden_spec_ids()
    @test !isempty(ids)
    for id in ids
        spec = load_golden_spec(id)
        @test String(spec.id) == id
        validate_golden_spec_schema!(spec)
        path = golden_dataset_path(spec)
        @test isfile(path)
        tol = golden_tolerance_dict(spec)
        @test !isempty(tol)
        for row in spec.tolerances
            @test haskey(tol, String(row.name))
            @test tol[String(row.name)] > 0 || row.name == "coefficient"
        end
    end
end
