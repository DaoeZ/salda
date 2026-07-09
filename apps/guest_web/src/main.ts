import { mount } from 'svelte';
import App from './App.svelte';
import { BRAND } from './lib/brand';
import './styles/tokens.g.css';
import './styles/base.css';

document.title = BRAND.appName;

const app = mount(App, { target: document.getElementById('app')! });

export default app;
