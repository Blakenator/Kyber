import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/server_settings_box.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class IngameSettings extends StatelessWidget {
  const IngameSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return KyberTable(
      itemStyle: const TextStyle(fontSize: 17),
      items: [
        KyberTableItem.custom(
          title: 'Shuffle Teams',
          onClick: () {
            final value =
                !(hostingForm.currentState!.fields['shuffleTeams']!.value
                    as bool);
            hostingForm.currentState?.fields['shuffleTeams']?.didChange(value);
            context.read<ModerationCubit>().sendCommand(
              '/Kyber.EnableShuffleTeams ${value ? '1' : '0'}',
            );
          },
          builder: (hovered) {
            return FormBuilderField<bool>(
              name: 'shuffleTeams',
              initialValue: false,
              builder: (field) {
                return KyberTableSwitch(
                  value: field.value,
                  hover: hovered,
                  onChanged: (value) {},
                );
              },
            );
          },
        ),
        KyberTableItem.custom(
          title: 'Bot Difficulty',
          builder: (hovered) {
            return FormBuilderField<int>(
              name: 'botDifficulty',
              initialValue: 3,
              builder: (field) {
                return KyberDropdown<int>(
                  items: [
                    DropdownItem(value: 12, label: 'Easy'),
                    DropdownItem(value: 9, label: 'Medium'),
                    DropdownItem(value: 6, label: 'Hard'),
                    DropdownItem(value: 3, label: 'Knight'),
                    DropdownItem(value: 0, label: 'Master'),
                  ],
                  selectedItem: field.value,
                  placeholder: 'SELECT DIFFICULTY',
                  itemBuilder: (item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          fontFamily: FontFamily.battlefrontUI,
                          fontSize: 18,
                        ),
                      ),
                    );
                  },
                  onChanged: (value) {
                    field.didChange(value);
                    context.read<ModerationCubit>().sendCommand(
                      '/AutoPlayers.AimNoiseScale $value',
                    );
                  },
                );
              },
            );
          },
        ),
        KyberTableItem.custom(
          title: 'Bots Light Side',
          builder: (hovered) {
            return FormBuilderField<int>(
              name: 'botsTeam1',
              initialValue: 0,
              builder: (field) {
                return KyberTableSlider(
                  min: 0,
                  max: 32,
                  value: field.value!,
                  hover: hovered,
                  onChanged: (value) {
                    field.didChange(value);
                    context.read<ModerationCubit>().botChangeStream!.add((
                      1,
                      value,
                    ));
                  },
                );
              },
            );
          },
        ),
        KyberTableItem.custom(
          title: 'Bots Dark Side',
          builder: (hovered) {
            return FormBuilderField<int>(
              name: 'botsTeam2',
              initialValue: 0,
              builder: (field) {
                return KyberTableSlider(
                  min: 0,
                  max: 32,
                  value: field.value!,
                  hover: hovered,
                  onChanged: (value) {
                    //TODO: throttle
                    field.didChange(value);
                    context.read<ModerationCubit>().botChangeStream!.add((
                      2,
                      value,
                    ));
                  },
                );
              },
            );
          },
        ),
        KyberTableItem.custom(
          title: 'Freeze Bots',
          onClick: () {
            final value =
                !(hostingForm.currentState!.fields['freezeBots']!.value
                    as bool);
            hostingForm.currentState?.fields['freezeBots']?.didChange(value);
            context.read<ModerationCubit>().sendCommand(
              '/AutoPlayers.UpdateAI ${value ? '0' : '1'}',
            );
          },
          builder: (hovered) {
            return FormBuilderField<bool>(
              name: 'freezeBots',
              initialValue: false,
              builder: (field) {
                return KyberTableSwitch(
                  value: field.value,
                  hover: hovered,
                  onChanged: (value) {},
                );
              },
            );
          },
        ),
        KyberTableItem.custom(
          title: 'Bots Ignore Players',
          onClick: () {
            final value =
                !(hostingForm.currentState!.fields['botsIgnorePlayers']!.value
                    as bool);
            hostingForm.currentState?.fields['botsIgnorePlayers']?.didChange(
              value,
            );
            context.read<ModerationCubit>().sendCommand(
              '/AutoPlayers.IgnoreHumanPlayers ${value ? '1' : '0'}',
            );
          },
          builder: (hovered) {
            return FormBuilderField<bool>(
              name: 'botsIgnorePlayers',
              initialValue: false,
              builder: (field) {
                return KyberTableSwitch(
                  value: field.value,
                  hover: hovered,
                  onChanged: (value) {},
                );
              },
            );
          },
        ),
      ],
    );
  }
}
