'use strict';
'require view';
'require form';
'require rpc';
'require fs';
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

	handleSave: null,
	handleSaveApply: null,
	handleReset: null,
});
