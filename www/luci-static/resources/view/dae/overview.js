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
});

const validateConfig = rpc.declare({
	object: "luci." + NAME,
	method: "validateConfig",
	params: ["content"],
});

function writeConfig(section_id, value) {
	// Preserve leading/trailing spaces and formatting as OpenWrt configs sometimes
	// rely on indentation/comments; only normalize line endings and ensure LF.
	var content = (value || '').replace(/\r\n/g, '\n');
	if (content.length === 0 || content[content.length - 1] !== '\n')
		content += '\n';

	return fs.write(CONF, content)
		.then(function() {
			return setInitAction(NAME, "reload_config");
		})
		.then(function(res) {
			var ok = (res && typeof res === 'object') ? res.result : res;
			if (ok === false)
				throw new Error(_('Failed to reload dae service.'));
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
			return fs.read_direct(CONF)
				.catch(function() { return ''; });
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
		})).then(function() {
			ui.addNotification(null, E('p', _('Configuration saved and reloaded.')), 'info');
		}).catch(function(err) {
			ui.addNotification(_('Save failed'), E('p', String(err)), 'error');
		});
	},

	handleSaveApply: null,
	handleReset: null,

	addFooter: function() {
		var self = this;
		var validateBtn = E('button', {
			'class': 'cbi-button cbi-button-neutral',
			'click': function() {
				validateBtn.disabled = true;
				var ta = document.querySelector('.cbi-section textarea');
				var content = ta ? ta.value : '';
				validateConfig(content).then(function(res) {
					validateBtn.disabled = false;
					if (res && res.valid) {
						ui.addNotification(null, E('p', '\u2713 ' + _('Config is valid')), 'info');
					} else {
						ui.addNotification(_('Validation failed'),
							E('p', res && res.message || _('Validation failed')), 'error');
					}
				}).catch(function(err) {
					validateBtn.disabled = false;
					ui.addNotification(_('Validation error'), E('p', String(err)), 'error');
				});
			},
		}, [_('Validate')]);

		var saveBtn = E('button', {
			'class': 'cbi-button cbi-button-save',
			'click': L.bind(self.handleSave, self),
		}, [_('Save')]);

		return E('div', { 'class': 'cbi-page-actions' }, [
			validateBtn, ' ', saveBtn,
		]);
	},
});
