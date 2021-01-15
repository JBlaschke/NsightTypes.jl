module NsightTypes

using JSON


# if I'm trying to parse an Int64 -> Int64 => pass through the value
Base.parse(::Type{Int64}, i::Integer) = i


#________________________________________________________________________________
# CUDA Kernel Type
#

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

export Kernel

#--------------------------------------------------------------------------------



#________________________________________________________________________________
# CUDA Event Type
#

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

export CudaEvent

#--------------------------------------------------------------------------------



#________________________________________________________________________________
# NVTX Types
#

struct NvtxEvent
    Type::Int64
    Timestamp::Int64
    Text::String
    GlobalTid::Int64
    EndTimestamp::Int64
    DomainId::Int64
    NsTime::Bool
end

function NvtxEvent(data)
    return NvtxEvent(
        parse(Int64, data["Type"]),
        parse(Int64, data["Timestamp"]),
        data["Text"],
        parse(Int64, data["GlobalTid"]),
        parse(Int64, data["EndTimestamp"]),
        parse(Int64, data["DomainId"]),
        data["NsTime"]
    )
end

export NvtxEvent


#________________________________________________________________________________
# Selector Types
# reverse-engineered from nsight profile. Note this might not be stable between
# nsight version
#

nsight_kernel_type = 79;
nsight_memcpy_type = 80;
nsight_nvtx_type   = 59;
iskernel(dict) = haskey(dict, "Type") && dict["Type"] == nsight_kernel_type;
ismemcpy(dict) = haskey(dict, "Type") && dict["Type"] == nsight_memcpy_type;
isnvtx(dict)   = haskey(dict, "Type") && dict["Type"] == nsight_nvtx_type;

export iskernel, ismemcpy, isnvtx

#--------------------------------------------------------------------------------



#________________________________________________________________________________
# Functions to analyze Events
#

startNs(evt::CudaEvent) = evt.startNs
endNs(evt::CudaEvent)   = evt.endNs

startNs(evt::NvtxEvent) = evt.Timestamp
endNs(evt::NvtxEvent)   = evt.EndTimestamp

lengthNs(evt::T) where T = endNs(evt) - startNs(evt)

function startNs(evts::Array{T, 1}) where T
    sorted = sort(evts, by = x -> x.startNs)
    sorted[1].startNs
end

function endNs(evts::Array{T, 1}) where T
    sorted = sort(evts, by = x -> x.endNs)
    sorted[end].endNs
end

lengthNs(evts::Array{T}) where T = endNs(evts) - startNs(evts)

contains(A::T1, B::T2) where {T1, T2} = startNs(A) < startNs(B) && endNs(B) < endNs(A)

function running_right_now(evts::Array{T, 1}, nowNs::Int64) where T
    running = Array{T, 1}(undef, 0)
    for evt in evts
        if evt.startNs < nowNs < evt.endNs
            push!(running, evt)
        end
    end
    return running
end

function contains(evts::Array{T, 1}, target_evt::Te) where {T, Te}
    running = Array{T, 1}(undef, 0)
    for evt in evts
        if contains(target_evt, evt)
            push!(running, evt)
        end
    end
    return running
end

export lengthNs, startNs, endNs, running_right_now, contains

#--------------------------------------------------------------------------------



#________________________________________________________________________________
# File IO
#

struct NsightProfile
    index
    events
end

function event_constructor(entry, nsight_index)
    if haskey(entry, "CudaEvent")
        return CudaEvent(entry["CudaEvent"], nsight_index)
    elseif haskey(entry, "NvtxEvent")
        return NvtxEvent(entry["NvtxEvent"])
    else
        throw("MalformedEntry")
    end
end

function load(nsight_prof, selector)
    io = open(nsight_prof);
    # first line is the index
    nsight_index = JSON.parse(readline(io));

    events = []
    while !eof(io)
        entry = JSON.parse(readline(io))
        if selector(entry)
            push!(events, event_constructor(entry, nsight_index))
        end
    end
    close(io)
    
    return NsightProfile(nsight_index, events)
end

export NsightProfile, load

#--------------------------------------------------------------------------------

end
