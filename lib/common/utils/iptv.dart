import 'dart:io';

import 'package:my_tv/common/index.dart';
import 'package:path_provider/path_provider.dart';

final _logger = LoggerUtil.create(['iptv']);

/// iptv工具类
class IptvUtil {
  IptvUtil._();

  /// 获取远程直播源类型
  static String _getSourceType() {
    final iptvSource = IptvSettings.customIptvSource.isNotEmpty ? IptvSettings.customIptvSource : Constants.iptvSource;

    if (iptvSource.endsWith('.m3u')) {
      return 'm3u';
    } else {
      return 'tvbox';
    }
  }

  /// 获取远程直播源
  static Future<String> _fetchSource() async {
    final iptvSource = IptvSettings.customIptvSource.isNotEmpty ? IptvSettings.customIptvSource : Constants.iptvSource;

    _logger.debug('获取远程直播源: $iptvSource');
    final result = await RequestUtil.get(iptvSource);
    return result;
  }

  /// 获取缓存直播源文件
  static Future<File> _getCacheFile() async {
    if (_getSourceType() == 'm3u') {
      return File('${(await getTemporaryDirectory()).path}/iptv.m3u');
    } else {
      return File('${(await getTemporaryDirectory()).path}/iptv-tvbox.txt');
    }
  }

  /// 获取缓存直播源
  static Future<String> _getCache() async {
    try {
      final cacheFile = await _getCacheFile();
      if (await cacheFile.exists()) {
        return await cacheFile.readAsString();
      }

      return '';
    } catch (e, st) {
      _logger.handle(e, st);
      return '';
    }
  }

  /// 解析直播源m3u
  static List<IptvGroup> _parseSourceM3u(String source) {
    var groupList = <IptvGroup>[];

    final lines = source.split('\n');

    var channel = 0;
    for (final (lineIdx, line) in lines.indexed) {
      if (line.isEmpty || !line.startsWith('#EXTINF:')) {
        continue;
      }

      final groupName = RegExp('group-title="(.*?)"').firstMatch(line)?.group(1) ?? '其他';
      final name = line.split(',')[1];

      if (IptvSettings.iptvSourceSimplify) {
        if (!name.toLowerCase().startsWith('cctv') && !name.endsWith('卫视')) continue;
      }

      final group = groupList.firstWhere((it) => it.name == groupName, orElse: () {
        final group = IptvGroup(idx: groupList.length, name: groupName, list: []);
        groupList.add(group);
        return group;
      });

      final iptv = Iptv(
        idx: group.list.length,
        channel: ++channel,
        groupIdx: group.idx,
        name: name,
        url: lines[lineIdx + 1],
        tvgName: RegExp('tvg-name="(.*?)"').firstMatch(line)?.group(1) ?? name,
      );

      group.list.add(iptv);
    }

    _logger.debug('解析m3u完成: ${groupList.length}个分组, $channel个频道');

    return groupList;
  }

  /// 解析直播源tvbox
  static List<IptvGroup> _parseSourceTvbox(String source) {
    var groupList = <IptvGroup>[];

    final lines = source.split('\n');

    var channel = 0;
    IptvGroup? group;
    for (final line in lines) {
      if (line.isEmpty) continue;

      if (line.endsWith('#genre#')) {
        final groupName = line.split(',')[0];
        group = IptvGroup(idx: groupList.length, name: groupName, list: []);
        groupList.add(group);
      } else {
        print(line);
        final name = line.split(',')[0];
        final url = line.split(',')[1];

        final iptv = Iptv(
          idx: group!.list.length,
          channel: ++channel,
          groupIdx: group.idx,
          name: name,
          url: url,
          tvgName: name,
        );

        group.list.add(iptv);
      }
    }

    _logger.debug('解析tvbox完成: ${groupList.length}个分组, $channel个频道');

    return groupList;
  }

  /// 解析直播源
  static List<IptvGroup> _parseSource(String source) {
    if (_getSourceType() == 'm3u') {
      return _parseSourceM3u(source);
    } else {
      return _parseSourceTvbox(source);
    }
  }

  /// 刷新并获取直播源
  static Future<List<IptvGroup>> refreshAndGet() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - IptvSettings.iptvSourceCacheTime < 24 * 60 * 60 * 1000) {
      final cache = await _getCache();

      if (cache.isNotEmpty) {
        _logger.debug('使用缓存直播源');
        return _parseSource(cache);
      }
    }

    final source = await _fetchSource();

    final cacheFile = await _getCacheFile();
    await cacheFile.writeAsString(source);
    IptvSettings.iptvSourceCacheTime = now;

    return _parseSource(source);
  }
}
