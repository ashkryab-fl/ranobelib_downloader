import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import 'models.dart';

String xmlEscape(String value) => const HtmlEscape(
  HtmlEscapeMode.element,
).convert(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');

class ContentParser {
  String chapterHtml(Json chapter) {
    final content = chapter['content'];
    if (content is String) return content;
    if (content is List) return _nodes(content, asList(chapter['attachments']));
    final data = asMap(content);
    return _nodes(asList(data['content']), asList(chapter['attachments']));
  }

  String summaryText(dynamic summary) {
    if (summary == null) return '';
    final rendered = summary is String
        ? summary
        : _nodes(asList(asMap(summary)['content']), []);
    final fragment = html.parseFragment(rendered);
    for (final br in fragment.querySelectorAll('br')) {
      br.replaceWith(dom.Text('\n'));
    }
    return fragment.text?.trim() ?? '';
  }

  String _nodes(List<dynamic> nodes, List<dynamic> attachments) =>
      nodes.map((node) => _node(asMap(node), attachments)).join();

  String _node(Json node, List<dynamic> attachments) {
    final type = textOf(node['type']);
    final attrs = asMap(node['attrs']);
    final children = _nodes(asList(node['content']), attachments);
    if (type == 'text') {
      var text = xmlEscape(
        decodeEntities(textOf(node['text'])),
      ).replaceAll('\n', '<br/>').replaceAll(RegExp(' +'), ' ');
      for (final rawMark in asList(node['marks']).reversed) {
        final mark = asMap(rawMark);
        final tag = switch (mark['type']) {
          'bold' => 'strong',
          'italic' => 'em',
          'underline' => 'u',
          'strike' => 's',
          'code' => 'code',
          'superscript' => 'sup',
          'subscript' => 'sub',
          _ => '',
        };
        if (tag.isNotEmpty) text = '<$tag>$text</$tag>';
        if (mark['type'] == 'link') {
          final href = textOf(asMap(mark['attrs'])['href']);
          if (_safeLink(href)) text = '<a href="${xmlEscape(href)}">$text</a>';
        }
      }
      return text;
    }
    if (type == 'hardBreak') return '<br/>';
    if (type == 'horizontalRule') return '<hr/>';
    if (type == 'image') {
      final images = asList(attrs['images']);
      if (images.isNotEmpty) {
        return images.map((image) {
          final id = asMap(image)['image'];
          final file = attachments
              .map(asMap)
              .where(
                (f) =>
                    textOf(f['name']) == textOf(id) ||
                    textOf(f['id']) == textOf(id),
              );
          if (file.isEmpty || textOf(file.first['url']).isEmpty) {
            throw FormatException('Не знайдено посилання на зображення $id.');
          }
          return '<img src="${xmlEscape(textOf(file.first['url']))}" alt=""/>';
        }).join();
      }
      final src = textOf(attrs['src']);
      if (src.isEmpty) {
        throw const FormatException('Зображення у главі не має посилання.');
      }
      return '<img src="${xmlEscape(src)}" alt="${xmlEscape(textOf(attrs['alt']))}"/>';
    }
    if (type == 'doc') return children;
    final tag = switch (type) {
      'paragraph' => 'p',
      'orderedList' => 'ol',
      'bulletList' => 'ul',
      'listItem' => 'li',
      'blockquote' => 'blockquote',
      'italic' => 'em',
      'bold' => 'strong',
      'underline' => 'u',
      'codeBlock' => 'pre',
      'table' => 'table',
      'tableRow' => 'tr',
      'tableCell' => 'td',
      'tableHeader' => 'th',
      'heading' =>
        'h${(int.tryParse(textOf(attrs['level'])) ?? 2).clamp(1, 6)}',
      _ => '',
    };
    if (tag.isEmpty) {
      return children.isNotEmpty
          ? children
          : '<pre>${xmlEscape(jsonEncode(node))}</pre>';
    }
    var attribute = '';
    if (tag == 'ol' && attrs['start'] != null) {
      attribute = ' start="${xmlEscape(textOf(attrs['start']))}"';
    }
    final align = textOf(attrs['textAlign']);
    if (['left', 'right', 'center', 'justify'].contains(align)) {
      attribute += ' style="text-align: $align"';
    }
    return '<$tag$attribute>${children.isEmpty ? '<br/>' : children}</$tag>';
  }

  bool _safeLink(String url) {
    final scheme = Uri.tryParse(url)?.scheme ?? '';
    return scheme.isEmpty || ['https', 'http', 'mailto'].contains(scheme);
  }

  Future<String> prepare(
    String rawHtml,
    Future<String> Function(String url) image,
  ) async {
    final fragment = html.parseFragment(rawHtml);
    for (final element in fragment.querySelectorAll(
      'script, style, iframe, object, embed',
    )) {
      element.remove();
    }
    for (final img in fragment.querySelectorAll('img')) {
      final url = img.attributes['src'] ?? img.attributes['data-src'];
      if (url == null || url.trim().isEmpty) {
        throw const FormatException('Зображення у главі не має посилання.');
      }
      img.attributes['src'] = 'images/${await image(url)}';
      img.attributes.remove('srcset');
    }
    final builder = XmlBuilder();
    for (final child in fragment.nodes) {
      _serialize(child, builder);
    }
    return builder
        .buildFragment()
        .children
        .map((node) => node.toXmlString())
        .join();
  }

  static const _tags = {
    'p',
    'div',
    'span',
    'br',
    'hr',
    'img',
    'strong',
    'b',
    'em',
    'i',
    'u',
    's',
    'del',
    'sup',
    'sub',
    'blockquote',
    'pre',
    'code',
    'ol',
    'ul',
    'li',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'table',
    'thead',
    'tbody',
    'tfoot',
    'tr',
    'td',
    'th',
    'caption',
    'a',
    'figure',
    'figcaption',
  };

  void _serialize(dom.Node node, XmlBuilder builder, {bool pre = false}) {
    if (node is dom.Text) {
      // XML 1.0 excludes control characters, even if valid in an HTML response.
      var text = node.data.replaceAll(
        RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F]'),
        '',
      );
      if (!pre) text = text.replaceAll('\n', ' ').replaceAll(RegExp(' +'), ' ');
      builder.text(text);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (!_tags.contains(tag)) {
      for (final child in node.nodes) {
        _serialize(child, builder, pre: pre);
      }
      return;
    }
    final attrs = <String, String>{};
    for (final entry in node.attributes.entries) {
      final key = entry.key.toString();
      if ([
            'title',
            'colspan',
            'rowspan',
            'start',
            'alt',
            'style',
          ].contains(key) ||
          (tag == 'img' && key == 'src') ||
          (tag == 'a' && key == 'href' && _safeLink(entry.value))) {
        attrs[key] = entry.value;
      }
    }
    builder.element(
      tag,
      attributes: attrs,
      nest: () {
        for (final child in node.nodes) {
          _serialize(child, builder, pre: pre || tag == 'pre');
        }
      },
    );
  }
}
