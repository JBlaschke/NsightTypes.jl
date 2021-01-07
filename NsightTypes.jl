module NsightTypes

using JSON

Base.parse(::Type{Int64}, i::Integer) = i

struct Kernel
    staticSharedMemory::Int64
    sharedMemoryConfig::Int64
    localMemoryTotal::Int64
    registersPerThread::Int64
    dynamicSharedMemory::Int64
    sharedMemoryExecuted::Int64
    blockX::Int64
    blockY::Int64
    blockZ::Int64
    gridX::Int64
    gridY::Int64
    gridZ::Int64
    gridId::Int64
    eventCategory::Int64
    launched::Int64
    shortName::String
end

Kernel(data, nsight_index) = 
    Kernel(
        parse(Int64, data["staticSharedMemory"]),
        parse(Int64, data["sharedMemoryConfig"]),
        parse(Int64, data["localMemoryTotal"]),
        parse(Int64, data["registersPerThread"]),
        parse(Int64, data["dynamicSharedMemory"]),
        parse(Int64, data["sharedMemoryExecuted"]),
        parse(Int64, data["blockX"]),
        parse(Int64, data["blockY"]),
        parse(Int64, data["blockZ"]),
        parse(Int64, data["gridX"]),
        parse(Int64, data["gridY"]),
        parse(Int64, data["gridZ"]),
        parse(Int64, data["gridId"]),
        parse(Int64, data["eventCategory"]),
        data["launched"],
        nsight_index["data"][parse(Int64, data["shortName"])]
    )

struct CudaEvent{T}
    deviceId::Int64
    streamId::Int64
    eventClass::Int64
    contextId::Int64
    correlationId::Int64
    globalPid::Int64
    startNs::Int64
    endNs::Int64
    data::T
end

function CudaEvent(data, nsight_index)

    if haskey(data, "kernel")
        payload = Kernel(data["kernel"], nsight_index)
    else
        throw("UnimplementedError")
    end
    
    return CudaEvent(
        parse(Int64, data["deviceId"]),
        parse(Int64, data["streamId"]),
        parse(Int64, data["eventClass"]),
        parse(Int64, data["contextId"]),
        parse(Int64, data["correlationId"]),
        parse(Int64, data["globalPid"]),
        parse(Int64, data["startNs"]),
        parse(Int64, data["endNs"]),
        payload
    )
end

# reverse-engineered from nsight profile. Note this might not be stable between
# nsight version
nsight_kernel_type = 79;
nsight_memcpy_type = 80;
iskernel(dict) = haskey(dict, "Type") && dict["Type"] == nsight_kernel_type;
ismemcpy(dict) = haskey(dict, "Type") && dict["Type"] == nsight_memcpy_type;


lengthNs(evt::CudaEvent) = evt.endNs - evt.startNs

function startNs(evts::Array{T, 1}) where T
    min_start_ns::Int64 = typemax(Int64)
    for evt in evts
        if evt.startNs < min_start_ns
            min_start_ns = evt.startNs
        end
    end
    return min_start_ns
end

function endNs(evts::Array{T, 1}) where T
    max_end_ns::Int64 = 0
    for evt in evts
        if evt.endNs > max_end_ns
            max_end_ns = evt.startNs
        end
    end
    return max_end_ns
end

lengthNs(evts::Array{T}) where T = endNs(evts) - startNs(evts)

function running_right_now(evts::Array{T, 1}, nowNs::Int64) where T
    running = Array{T, 1}(undef, 0)
    for evt in evts
        if evt.startNs < nowNs < evt.endNs
            push!(running, evt)
        end
    end
    return running
end


struct NsightProfile
    index
    events
end


function load(nsight_prof)
    io = open(nsight_prof);
    # first line is the index
    nsight_index = JSON.parse(readline(io));

    kernels = []
    while !eof(io)
        entry = JSON.parse(readline(io))
        if iskernel(entry)
            push!(kernels, CudaEvent(entry["CudaEvent"], nsight_index))
        end
    end
    close(io)
    
    return NsightProfile(nsight_index, kernels)
end

end