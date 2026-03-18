'use strict';
'require view';
'require form';
'require rpc';
'require fs';
'require ui';
"require dae.status as status";
"require dae.log as log";

const NAME = "dae";
const CONF = "/etc/dae/config.dae";

const setInitAction = rpc.declare({
	object: "luci." + NAME,
	method: "setInitAction",
	params: ["name", "action"],
	expect: { result: false },
});

const validateConfig = rpc.declare({
	object: "luci." + NAME,
	method: "validateConfig",
});

function writeConfig(section_id, value) {
	return fs.write(CONF, (value || '').trim().replace(/\r\n/g, '\n') + '\n')
		.then(function() {
			setInitAction(NAME, "reload_config");
			location.reload();
		});
}

return view.extend({
	render: function() {
		var stat, m, s, o;

		stat = new status.getStatus();

		m = new form.Map('dae', 'dae',
			_('eBPF-based Linux high-performance transparent proxy solution.'));

		s = m.section(form.NamedSection, 'settings', 'settings');

		s.tab('config', _('Config'));

		o = s.taboption('config', form.TextValue, '_config');
		o.rows = 32;
		o.load = function(section_id) {
			return fs.trimmed(CONF);
		};
		o.write = writeConfig;
		o.remove = writeConfig;

		s.tab('log', _('Log'));

		o = s.taboption('log', form.DummyValue, '_dae_logview');
		o.render = L.bind(log.getRuntimeLog, this);

		return Promise.all([stat.render(), m.render()]);
	},

	handleSave: function(ev) {
		var maps = (document.getElementById('view') || E([])).querySelectorAll('.cbi-map');
		return Promise.all(Array.prototype.map.call(maps, function(map) {
			var m = L.dom.findClassInstance(map);
			return m ? m.save() : Promise.resolve();
		}));
	},

	handleSaveApply: null,
	handleReset: null,

	addFooter: function() {
		var self = this;
		var resultEl = E('span', { style: 'margin-left:12px;font-size:.9em;vertical-align:middle' }, '');

		var validateBtn = E('button', {
			'class': 'cbi-button cbi-button-neutral',
			'click': function() {
				validateBtn.disabled = true;
				resultEl.style.color = '#888';
				resultEl.textContent = '\u23f3 ' + _('Validating...');
				validateConfig().then(function(res) {
					validateBtn.disabled = false;
					if (res && res.valid) {
						resultEl.style.color = 'green';
						resultEl.textContent = '\u2713 ' + _('Config is valid');
					} else {
						resultEl.style.color = 'red';
						resultEl.textContent = '\u2717 ' + (res && res.message || _('Validation failed'));
					}
				}).catch(function(err) {
					validateBtn.disabled = false;
					resultEl.style.color = 'red';
					resultEl.textContent = '\u2717 ' + String(err);
				});
			},
		}, [_('Validate')]);

		var saveBtn = E('button', {
			'class': 'cbi-button cbi-button-save',
			'click': L.bind(self.handleSave, self),
		}, [_('Save')]);

		return E('div', { 'class': 'cbi-page-actions' }, [
			validateBtn, ' ', resultEl, ' ', saveBtn,
		]);
	},
});
