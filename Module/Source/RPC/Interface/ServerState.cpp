// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#define _WINSOCKAPI_
#include <RPC/Interface/ServerState.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <Utilities/StringUtils.h>

#include <grpcpp/support/status.h>

namespace Kyber
{
using grpc::Status;

using namespace fastdelegate;
using namespace kyber_interface;

ServerUnaryReactor* ServerInterfaceService::StartServer(
    CallbackServerContext* context, const StartServerRequest* request, ServerState* response)
{
    ServerUnaryReactor* reactor = context->DefaultReactor();

    g_program->m_server->m_mapRotation.Reset();
    for (const auto& entry : request->maprotation())
    {
        g_program->m_server->m_mapRotation.AddEntry(entry.map(), entry.mode());
    }

    ServerCreationInfo info;
    info.name = request->name();
    info.description = request->description();
    info.password = request->password();

    auto entry = g_program->m_server->m_mapRotation.GetNextEntry();
    info.level = entry.level;
    info.mode = entry.mode;

    info.maxPlayers = request->maxplayers();

    g_program->m_server->Start(info);

    reactor->Finish(Status::OK);
    return reactor;
}

ServerUnaryReactor* ServerInterfaceService::LoadLevel(
    CallbackServerContext* context, const kyber_interface::LoadLevelRequest* request, kyber_common::Empty* response)
{
    KYBER_LOG(Info, "[Server] Loading remotely requested level");

    const auto& setup = request->levelsetup();
    g_program->m_server->LoadNextLevel(setup.map().c_str(), setup.mode().c_str());

    ServerUnaryReactor* reactor = context->DefaultReactor();
    reactor->Finish(Status::OK);
    return reactor;
}

ServerUnaryReactor* ServerInterfaceService::SetMapRotation(
    CallbackServerContext* context, const kyber_interface::SetMapRotationRequest* request, kyber_common::Empty* response)
{
    KYBER_LOG(Info, "[Server] Updating map rotation");

    g_program->m_server->m_mapRotation.Reset();
    for (const auto& entry : request->rotation())
    {
        g_program->m_server->m_mapRotation.AddEntry(entry.map(), entry.mode());
    }

    // Point the rotation at the entry following the currently playing map, so the
    // next auto-rotation/restart advances to the map after `current` rather than
    // reloading the map the server is already on.
    const auto entryCount = g_program->m_server->m_mapRotation.GetEntries().size();
    if (entryCount > 0)
    {
        const uint32_t safeCurrent = request->current() < entryCount ? request->current() : static_cast<uint32_t>(entryCount - 1);
        g_program->m_server->m_mapRotation.SetCurrentIndex(static_cast<uint16_t>((safeCurrent + 1) % entryCount));
    }

    ServerUnaryReactor* reactor = context->DefaultReactor();
    reactor->Finish(Status::OK);
    return reactor;
}
} // namespace Kyber
