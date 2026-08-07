// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#define _WINSOCKAPI_
// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#include <RPC/Interface/Common.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <grpcpp/support/status.h>

#include <FastDelegate.h>
#include <mutex>

namespace Kyber
{
using grpc::Status;
using grpc::StatusCode;

using namespace kyber_interface;

ServerUnaryReactor* CommonInterfaceService::GetInfo(
    CallbackServerContext* context, const kyber_common::Empty* request, kyber_interface::CommonState* response)
{
    ServerUnaryReactor* reactor = context->DefaultReactor();

    if (g_program->m_server->IsRunning() && g_program->m_server->m_serverInstance != nullptr)
    {
        kyber_interface::ServerState* server = response->mutable_server();
        server->set_id(g_program->m_server->m_serverId);

        server->mutable_levelsetup()->set_map(g_program->m_server->m_currentLevel);
        server->mutable_levelsetup()->set_mode(g_program->m_server->m_currentMode);

        // Report the position of the currently playing map within the rotation
        uint32_t mapRotationIndex = 0;
        const auto& rotationEntries = g_program->m_server->m_mapRotation.GetEntries();
        for (size_t i = 0; i < rotationEntries.size(); ++i)
        {
            if (rotationEntries[i].level == g_program->m_server->m_currentLevel &&
                rotationEntries[i].mode == g_program->m_server->m_currentMode)
            {
                mapRotationIndex = static_cast<uint32_t>(i);
                break;
            }
        }
        server->set_maprotationindex(mapRotationIndex);

        for (const auto& entry : rotationEntries)
        {
            kyber_common::LevelSetup* setup = server->add_maprotation();
            setup->set_map(entry.level);
            setup->set_mode(entry.mode);
        }

        for (ServerPlayer* player : g_program->m_server->m_playerManager->m_players)
        {
            if (player->IsAIPlayer())
            {
                continue;
            }

            kyber_common::ServerPlayer* protoPlayer = server->add_playerlist();
            protoPlayer->set_id(std::to_string(player->m_onlineId.m_nativeData));
            protoPlayer->set_name(player->m_name);
            protoPlayer->set_teamid(player->m_teamId);
        }
    }
    else if (g_program->m_client->m_connected)
    {
        response->mutable_client()->set_serverid(g_program->m_server->m_socketSpawnInfo.serverName);
    }

    bool vivoxInitialized =
        g_program->m_client->m_voipManager != nullptr && !g_program->m_client->m_voipManager->GetRenderDevices().empty();
    response->set_vivoxinitialized(vivoxInitialized);

    reactor->Finish(Status::OK);
    return reactor;
}

ServerUnaryReactor* CommonInterfaceService::RunCommand(
    CallbackServerContext* context, const kyber_interface::RunCommandRequest* request, kyber_common::Empty* response)
{
    ServerUnaryReactor* reactor = context->DefaultReactor();

    auto delegate = fastdelegate::FastDelegate<void(const char*)>([](const char* result) {
        if (strlen(result) == 0)
        {
            return;
        }

        KYBER_LOG(Info, "[Console] Result: " << result);
    });
    Console_enqueueCommand(request->command().c_str(), delegate);

    reactor->Finish(Status::OK);
    return reactor;
}

} // namespace Kyber
