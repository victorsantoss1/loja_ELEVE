/*
 * Mini-runtime para abrir o protótipo fora do canvas de design.
 *
 * O design (design/canvas/Main.dc.html) usa um formato de template simples:
 *   {{caminho.do.valor}}  -> valor vindo de renderVals()
 *   <sc-if value="{{x}}"> -> mostra o conteúdo se x for verdadeiro
 *   <sc-for list="{{lista}}" as="item"> -> repete o conteúdo para cada item
 * e uma classe `Component extends DCLogic` com estado e eventos.
 *
 * Este arquivo interpreta esse formato com React, sem build e sem dependências
 * além de react/react-dom (em ./vendor). É só para visualizar o protótipo:
 * o app real deve ser construído do zero seguindo docs/PROMPT.md.
 */
(function () {
  'use strict';

  var h = React.createElement;
  var HOLE = /\{\{\s*([^}]+?)\s*\}\}/g;
  var WHOLE = /^\s*\{\{\s*([^}]+?)\s*\}\}\s*$/;

  // Atributos que o parser HTML deixa em minúsculas e o React espera em camelCase.
  var ATTR = {
    'class': 'className',
    'for': 'htmlFor',
    'onclick': 'onClick',
    'onchange': 'onChange',
    'oninput': 'onInput',
    'onkeydown': 'onKeyDown',
    'onsubmit': 'onSubmit',
    'autocomplete': 'autoComplete',
    'inputmode': 'inputMode',
    'enterkeyhint': 'enterKeyHint',
    'tabindex': 'tabIndex',
    'readonly': 'readOnly',
    'maxlength': 'maxLength',
    'crossorigin': 'crossOrigin',
    'viewbox': 'viewBox',
    'stroke-width': 'strokeWidth',
    'stroke-linecap': 'strokeLinecap',
    'stroke-linejoin': 'strokeLinejoin',
    'stroke-dasharray': 'strokeDasharray',
    'fill-rule': 'fillRule',
    'clip-rule': 'clipRule'
  };

  function lookup(scope, expr) {
    if (expr === 'true') return true;
    if (expr === 'false') return false;
    if (expr === 'null') return null;
    if (/^-?\d+(\.\d+)?$/.test(expr)) return Number(expr);
    var parts = expr.split('.');
    var v = scope;
    for (var i = 0; i < parts.length; i++) {
      if (v == null) return undefined;
      v = v[parts[i]];
    }
    return v;
  }

  function interp(str, scope) {
    var m = str.match(WHOLE);
    if (m) return lookup(scope, m[1]);
    return str.replace(HOLE, function (_, e) {
      var v = lookup(scope, e);
      return v == null ? '' : String(v);
    });
  }

  function camel(prop) {
    if (prop.indexOf('--') === 0) return prop;
    return prop.replace(/-([a-z])/g, function (_, c) { return c.toUpperCase(); });
  }

  function parseStyle(css) {
    var out = {};
    String(css).split(';').forEach(function (decl) {
      var i = decl.indexOf(':');
      if (i < 0) return;
      var k = decl.slice(0, i).trim();
      var v = decl.slice(i + 1).trim();
      if (k) out[camel(k)] = v;
    });
    return out;
  }

  // Converte o DOM do <template> numa árvore simples, uma vez só.
  function compile(node) {
    if (node.nodeType === 3) {
      var t = node.nodeValue;
      if (!t.trim() && t.indexOf('\n') >= 0) return null;
      return { text: t, dyn: t.indexOf('{{') >= 0 };
    }
    if (node.nodeType !== 1) return null;
    var attrs = [];
    for (var i = 0; i < node.attributes.length; i++) {
      var a = node.attributes[i];
      if (a.name.indexOf('hint-') === 0) continue;
      attrs.push({ name: ATTR[a.name] || a.name, raw: a.value, dyn: a.value.indexOf('{{') >= 0 });
    }
    var kids = [];
    for (var j = 0; j < node.childNodes.length; j++) {
      var c = compile(node.childNodes[j]);
      if (c) kids.push(c);
    }
    return { tag: node.localName, attrs: attrs, kids: kids };
  }

  function attrOf(n, name) {
    for (var i = 0; i < n.attrs.length; i++) if (n.attrs[i].name === name) return n.attrs[i].raw;
    return '';
  }

  function renderKids(kids, scope) {
    var out = [];
    for (var i = 0; i < kids.length; i++) {
      var r = render(kids[i], scope, i);
      if (r !== null && r !== undefined && r !== false) out.push(r);
    }
    return out;
  }

  function render(n, scope, key) {
    if (n.text !== undefined) return n.dyn ? interp(n.text, scope) : n.text;

    if (n.tag === 'sc-if') {
      if (!interp(attrOf(n, 'value'), scope)) return null;
      return h.apply(null, [React.Fragment, { key: key }].concat(renderKids(n.kids, scope)));
    }

    if (n.tag === 'sc-for') {
      var list = interp(attrOf(n, 'list'), scope) || [];
      var as = attrOf(n, 'as') || 'item';
      return h(React.Fragment, { key: key }, list.map(function (item, idx) {
        var s = Object.create(scope);
        s[as] = item;
        s.$index = idx;
        return h.apply(null, [React.Fragment, { key: idx }].concat(renderKids(n.kids, s)));
      }));
    }

    if (n.tag === 'helmet') return null;

    var props = { key: key };
    for (var i = 0; i < n.attrs.length; i++) {
      var a = n.attrs[i];
      var val = a.dyn ? interp(a.raw, scope) : a.raw;
      if (val === undefined) continue;
      if (a.name === 'style') { props.style = typeof val === 'string' ? parseStyle(val) : val; continue; }
      props[a.name] = val;
    }
    if (n.tag === 'input' && props.value !== undefined && !props.onChange) props.readOnly = true;
    return h.apply(null, [n.tag, props].concat(renderKids(n.kids, scope)));
  }

  var TREE = null;

  function tree() {
    if (!TREE) {
      var tpl = document.getElementById('dc-template');
      var root = { tag: '#root', attrs: [], kids: [] };
      var nodes = tpl.content.childNodes;
      for (var i = 0; i < nodes.length; i++) {
        var c = compile(nodes[i]);
        if (c) root.kids.push(c);
      }
      TREE = root;
    }
    return TREE;
  }

  class DCLogic extends React.Component {
    render() {
      var vals = this.renderVals ? this.renderVals() : {};
      return h.apply(null, [React.Fragment, null].concat(renderKids(tree().kids, vals)));
    }
  }

  function mount(Component) {
    var q = new URLSearchParams(location.search);
    var props = {};
    if (q.get('cenario')) props.cenario = q.get('cenario');
    if (q.get('perfil')) props.perfil = q.get('perfil');
    ReactDOM.createRoot(document.getElementById('root')).render(h(Component, props));
  }

  window.DCLogic = DCLogic;
  window.DC = { mount: mount };
})();
