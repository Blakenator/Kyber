import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_status_cubit.dart';
import 'package:kyber_launcher/features/kyber/services/map_helper.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';

class HostingBackgroundImage extends StatelessWidget {
  const HostingBackgroundImage({super.key});

  String getMapName(BuildContext context) {
    final state = context.read<KyberStatusCubit>().state;
    if (state is KyberStatusHosting) {
      final rotation = state.serverState.mapRotation;
      final index = state.serverState.mapRotationIndex;
      if (index < rotation.length) {
        return rotation[index].map;
      }
    }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KyberStatusCubit, KyberStatusState>(
      builder: (context, state) {
        final mapName = getMapName(context);
        final image = mapName.isNotEmpty
            ? MapHelper.getImageForMap(mapName) ?? Assets.images.kyberNoImage
            : Assets.images.kyberNoImage;
        return SizedBox(
          height: 200,
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.7),
              BlendMode.srcATop,
            ),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 6,
                sigmaY: 6,
                tileMode: TileMode.mirror,
              ),
              child: image.image(
                height: 200,
                fit: BoxFit.fitWidth,
                key: Key(mapName.isNotEmpty ? mapName : 'no-image'),
              ),
            ),
          ),
        );
      },
    );
  }
}
