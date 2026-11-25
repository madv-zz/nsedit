#!/usr/bin/env python3
"""Browser test for the nsedit web interface (jQuery, jQuery UI and jTable) with Playwright/Chromium.

Usage: tests/ui.py [base-url]      (default base-url: http://127.0.0.1:8080)

Runs in the Playwright image, for example:
    docker run --rm --network host -v "$PWD:/src:ro" -w /src mcr.microsoft.com/playwright/python:v1.65.1-noble \
        sh -c 'pip install -q playwright==1.65.1 && python3 -I tests/ui.py'

Reads NSEDIT_ADMIN_USER / NSEDIT_ADMIN_PASSWORD from .env (never prints them). Fails on every JavaScript
error, failed request or console error/warning, so a library update that breaks the UI is caught.
Creates and removes the zones uitest.example. and 113.0.203.in-addr.arpa. and the user uitest@example.com.
"""
import os
import re
import sys

from playwright.sync_api import expect, sync_playwright

BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:8080'
ZONE = 'uitest.example.'
REVZONE = '113.0.203.in-addr.arpa.'  # made through 'Add reverse zones' for 203.0.113.0/24
USER = 'uitest@example.com'
EXPECTED = {'jQuery.fn.jquery': '3.7.1', 'jQuery.ui.version': '1.14.2'}

env = {}
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.env'), encoding='utf-8') as envfile:
    for line in envfile:
        if '=' in line and not line.startswith('#'):
            k, v = line.rstrip('\n').split('=', 1)
            env[k] = v

problems = []
step_count = 0
ignore_answers = False  # True while cleaning up leftovers: errors there are expected


def step(name):
    global step_count
    step_count += 1
    print(f'ok   {name}')


def collect(page):
    page.on('pageerror', lambda exc: problems.append(f'JavaScript error: {exc}\n{exc.stack}'))
    page.on('console', lambda msg: problems.append(f'console {msg.type}: {msg.text}')
            if msg.type in ('error', 'warning') else None)
    page.on('requestfailed', lambda req: problems.append(f'request failed: {req.url} {req.failure}'))
    page.on('response', lambda resp: problems.append(f'HTTP {resp.status}: {resp.url}')
            if resp.status >= 400 else None)
    page.on('response', check_jtable_answer)


def dialog_button(page, button_id):
    """Every jTable has its own dialogs with the same button ids: click the one in the visible dialog."""
    button = page.locator(f'.ui-dialog:visible #{button_id}')
    expect(button).to_have_count(1)  # dialogs that are still fading out also count as visible
    button.click()


def check_jtable_answer(resp):
    """jTable gets HTTP 200 also for errors; the JSON says Result=ERROR with a Message."""
    if ignore_answers or '.php?action=' not in resp.url or 'json' not in (resp.headers.get('content-type') or ''):
        return
    try:
        body = resp.json()
    except Exception:  # noqa: BLE001 - not JSON after all
        return
    if isinstance(body, dict) and body.get('Result') == 'ERROR':
        problems.append(f"nsedit error on {resp.url.split('/')[-1]}: {body.get('Message')}")


def search_zones(page, text):
    """The search field reloads the zone list 400 ms after typing: wait for that answer, so the test never
    clicks a row that is about to be replaced."""
    with page.expect_response(lambda r: re.search(r'zones\.php\?action=list(&|$)', r.url) is not None):
        page.fill('#domsearch', text)
    expect(page.locator('#MasterZones .jtable-busy-message')).to_be_hidden()


def master_row(page, name):
    return page.locator('#MasterZones > .jtable-main-container > table > tbody > tr.jtable-data-row',
                        has=page.locator('td', has_text=re.compile('^' + re.escape(name) + '$')))


def child_table(page):
    return page.locator('#MasterZones .jtable-child-table-container')


def cleanup(page):
    """Remove leftovers of an earlier run through the API of nsedit itself (same session and csrf token)."""
    page.evaluate("""async ([zones, user]) => {
        const post = (url, data) => fetch(url, {method: 'POST', body: new URLSearchParams(data),
            headers: {'X-CSRF-Token': window.csrf_token}}).then(r => r.json()).catch(() => null);
        for (const z of zones) await post('zones.php?action=delete', {id: z});
        const users = await post('users.php?action=list', {});
        for (const u of (users && users.Records) || []) {
            if (u.emailaddress === user) await post('users.php?action=delete', {id: u.id});
        }
    }""", [[ZONE, REVZONE], USER])


def zones(page):
    page.click('#zoneadmin')
    page.click('#MasterZones .jtable-toolbar-item-add-record')
    form = page.locator('.ui-dialog:visible #jtable-create-form')
    form.locator('#Edit-name').fill(ZONE)
    expect(form.locator('#Edit-moverecords')).to_be_checked()
    expect(form.locator('#nameservers input[name="nameserver[]"]').first).to_be_visible()
    dialog_button(page, 'AddRecordDialogSaveButton')
    expect(master_row(page, ZONE)).to_have_count(1)
    expect(page.locator('.ui-dialog:visible')).to_have_count(0)
    step('create zone through the dialog')

    master_row(page, ZONE).locator('td.domain').click()
    expect(child_table(page).locator('.jtable-title-text')).to_contain_text('Records in ' + ZONE)
    expect(child_table(page).locator('td.type', has_text='SOA')).to_have_count(1)
    step('open the records of the zone')

    child_table(page).locator('.jtable-toolbar-item-add-record').click()
    form = page.locator('.ui-dialog:visible #jtable-create-form')
    form.locator('#Edit-name').fill('www')
    form.locator('#Edit-type').select_option('A')
    form.locator('#Edit-content').fill('192.0.2.50')
    dialog_button(page, 'AddRecordDialogSaveButton')
    row = child_table(page).locator('tr.jtable-data-row', has_text='192.0.2.50')
    expect(row).to_have_count(1)
    step('add record')

    expect(page.locator('.ui-dialog:visible')).to_have_count(0)  # the add dialog fades out
    child_table(page).locator('.jtable-toolbar-item-add-record').click()
    form = page.locator('.ui-dialog:visible #jtable-create-form')
    expect(form.locator('#Edit-name')).to_have_attribute('title', re.compile('relative to the zone'))
    page.locator('.ui-dialog:visible').get_by_role('button', name='Cancel').click()
    expect(page.locator('.ui-dialog:visible')).to_have_count(0)
    step('tooltip on the Label field of a forward zone')

    row.locator('.jtable-edit-command-button').click()
    form = page.locator('.ui-dialog:visible #jtable-edit-form')
    form.locator('#Edit-content').fill('192.0.2.51')
    dialog_button(page, 'EditDialogSaveButton')
    row = child_table(page).locator('tr.jtable-data-row', has_text='192.0.2.51')
    expect(row).to_have_count(1)
    step('edit record')

    row.locator('.jtable-delete-command-button').click()
    dialog_button(page, 'DeleteDialogButton')
    expect(child_table(page).locator('tr.jtable-data-row', has_text='192.0.2.51')).to_have_count(0)
    step('delete record')

    child_table(page).locator('.jtable-toolbar-item', has_text='Search zone').click()
    dialog = page.locator('.ui-dialog', has=page.locator('#searchzone'))
    expect(dialog).to_be_visible()
    page.fill('#searchzone-label', 'nothing-matches')
    dialog.get_by_role('button', name='Search').click()
    expect(child_table(page).locator('.jtable-title-text')).to_contain_text('(filtered)')
    expect(child_table(page).locator('tr.jtable-data-row')).to_have_count(0)
    child_table(page).locator('.jtable-toolbar-item', has_text='Search zone').click()
    dialog.get_by_role('button', name='Reset').click()
    expect(child_table(page).locator('td.type', has_text='SOA')).to_have_count(1)
    step('search records (jQuery UI dialog)')

    with page.expect_download() as download:
        master_row(page, ZONE).locator('img[title="Export zone"]').click()
    path = download.value.path()
    with open(path, encoding='utf-8') as exported:
        text = exported.read()
    if 'SOA' not in text:
        problems.append('exported zone has no SOA record')
    step('export zone (download)')

    search_zones(page, 'uitest')
    expect(master_row(page, ZONE)).to_have_count(1)
    step('search zones')

    page.locator('#MasterZones .jtable-toolbar-item', has_text='Clone a zone').click()
    clone = page.locator('.ui-dialog', has=page.locator('#Edit-destname'))
    expect(clone).to_be_visible()
    clone.get_by_role('button', name='Cancel').click()
    expect(clone).to_be_hidden()
    step('clone dialog opens and closes')

    page.locator('#MasterZones .jtable-toolbar-item', has_text='Add reverse zones').click()
    form = page.locator('.ui-dialog:visible #jtable-create-form')
    form.locator('#Edit-prefixes').fill('203.0.113.0/24')
    expect(form.locator('#Edit-moverecords')).to_be_checked()
    expect(form.locator('input[name="nameserver[]"]').first).to_be_visible()
    dialog_button(page, 'AddRecordDialogSaveButton')
    result = page.locator('.ui-dialog', has=page.locator('#reverseresult'))
    expect(result).to_be_visible()
    expect(result).to_contain_text('Created (1)')
    expect(result).to_contain_text(REVZONE)
    result.locator('.ui-dialog-buttonpane button', has_text='Close').click()
    expect(result).to_be_hidden()
    search_zones(page, '113.0.203')
    expect(master_row(page, REVZONE)).to_have_count(1)
    master_row(page, REVZONE).locator('.jtable-delete-command-button').click()
    dialog_button(page, 'DeleteDialogButton')
    expect(master_row(page, REVZONE)).to_have_count(0)
    step('add reverse zones for a prefix, then delete the zone')


def reverse_ptr(page):
    """Reverse zone: the Label tooltip names an address of the zone; a PTR can be added by IP address."""
    page.click('#zoneadmin')
    page.click('#MasterZones .jtable-toolbar-item-add-record')
    form = page.locator('.ui-dialog:visible #jtable-create-form')
    form.locator('#Edit-name').fill(REVZONE)
    dialog_button(page, 'AddRecordDialogSaveButton')
    expect(page.locator('.ui-dialog:visible')).to_have_count(0)
    search_zones(page, '113.0.203')
    master_row(page, REVZONE).locator('td.domain').click()
    expect(child_table(page).locator('.jtable-title-text')).to_contain_text('Records in ' + REVZONE)
    child_table(page).locator('.jtable-toolbar-item-add-record').click()
    form = page.locator('.ui-dialog:visible #jtable-create-form')
    expect(form.locator('#Edit-name')).to_have_attribute('title', re.compile(r'IP address \(e\.g\. 203\.0\.113\.10\)'))
    step('tooltip on the Label field of a reverse zone')

    form.locator('#Edit-name').fill('203.0.113.25')
    form.locator('#Edit-type').select_option('PTR')
    form.locator('#Edit-content').fill('host25.example')
    dialog_button(page, 'AddRecordDialogSaveButton')
    expect(child_table(page).locator('tr.jtable-data-row', has_text='host25.example.')).to_have_count(1)
    step('add PTR by IP address through the dialog')

    search_zones(page, 'in-addr.arpa')  # reloads the zone list, which closes the open record table
    master_row(page, REVZONE).locator('.jtable-delete-command-button').click()
    dialog_button(page, 'DeleteDialogButton')
    expect(master_row(page, REVZONE)).to_have_count(0)


def users(page):
    page.click('#useradmin')
    expect(page.locator('#Users td', has_text=env['NSEDIT_ADMIN_USER'])).to_have_count(1)
    page.click('#Users .jtable-toolbar-item-add-record')
    form = page.locator('.ui-dialog:visible #jtable-create-form')
    form.locator('#Edit-emailaddress').fill(USER)
    form.locator('#Edit-password').fill('Uitest-password-123')
    dialog_button(page, 'AddRecordDialogSaveButton')
    row = page.locator('#Users tr.jtable-data-row', has_text=USER)
    expect(row).to_have_count(1)
    step('add user')
    row.locator('.jtable-delete-command-button').click()
    dialog_button(page, 'DeleteDialogButton')
    expect(page.locator('#Users tr.jtable-data-row', has_text=USER)).to_have_count(0)
    step('delete user')


def logs(page):
    page.click('#logadmin')
    expect(page.locator('#Logs td', has_text='Created zone ' + ZONE).first).to_be_visible()
    step('logs show the actions')


def delete_zone(page):
    page.click('#zoneadmin')
    search_zones(page, '')
    master_row(page, ZONE).locator('.jtable-delete-command-button').click()
    dialog_button(page, 'DeleteDialogButton')
    expect(master_row(page, ZONE)).to_have_count(0)
    step('delete zone')


def main():
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page(accept_downloads=True)
        page.set_default_timeout(15000)
        collect(page)

        page.goto(BASE + '/index.php')
        page.fill('input[name=username]', env['NSEDIT_ADMIN_USER'])
        page.fill('input[name=password]', env['NSEDIT_ADMIN_PASSWORD'])
        page.click('input[type=submit]')
        expect(page.locator('#zoneadmin')).to_be_visible()
        step('login')

        for expression, version in EXPECTED.items():
            got = page.evaluate(expression)
            if got != version:
                problems.append(f'{expression} is {got}, expected {version}')
        step('library versions')

        global ignore_answers
        ignore_answers = True
        cleanup(page)
        ignore_answers = False
        page.reload()
        expect(page.locator('#MasterZones .jtable-main-container')).to_be_visible()

        try:
            zones(page)
            reverse_ptr(page)
            users(page)
            logs(page)
            delete_zone(page)
        except Exception:
            shot = os.environ.get('UI_SCREENSHOT')
            if shot:
                page.screenshot(path=shot, full_page=True)
            for problem in problems:
                print('FAIL ' + problem)
            raise

        page.click('text=Logout')
        expect(page.locator('input[name=username]')).to_be_visible()
        step('logout')
        browser.close()

    for problem in problems:
        print('FAIL ' + problem)
    print(f'\n{step_count} steps, {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
