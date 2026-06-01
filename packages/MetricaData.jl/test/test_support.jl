using CSV
using DataFrames

function with_temp_csv(f::Function, df::DataFrame)
    path = tempname() * ".csv"
    CSV.write(path, df)
    try
        return f(path)
    finally
        rm(path; force = true)
    end
end
