#!/usr/bin/env python3
#
# mod_pack_maker.py
#
# Usage:
#     python3 mod_pack_maker.py build --mod /path/to/extracted/modpack
#
#

import argparse
import datetime
import json
import os
import sys
import time
import traceback

from selenium import webdriver
from selenium.common.exceptions import NoSuchElementException, TimeoutException
from selenium.webdriver.common.by import By
from selenium.webdriver.firefox.options import Options as FirefoxOptions
from selenium.webdriver.support import expected_conditions as exp_cond
from selenium.webdriver.support.ui import WebDriverWait

# Valid modpack maker commands
valid_commands = ['build']

# The XPath expression of the project ID on the Forge MineCraft mod page
xpath_expression = '/html/body/div[1]/main/div[2]/aside/div[2]/section[1]/dl/dd[3]'

# Local directory to store mappings
minecraft_dir = os.path.join(os.path.expanduser('~'), '.minecraft')

# Mapping file for project URLs to IDs, and other info
mapping_file = os.path.join(minecraft_dir, 'project_info.json')


class ModpackMakerError(Exception):
    """Errors with the modpack maker"""


def build(args):
    """Build a server mod pack from the provided client mod pack

    :param args: (argparse)
    :return:
    """

    # Get the mod directory from the args
    mod_dir = args.mod

    # Ensure the mod directory exists
    if not os.path.isdir(mod_dir):
        print('ERROR: Mod directory not found: {d}'.format(d=mod_dir))
        return 1

    # Mod files
    modlist_html_file = os.path.join(mod_dir, 'modlist.html')
    manifest_json_file = os.path.join(mod_dir, 'manifest.json')
    mod_file_dir = os.path.join(mod_dir, 'mods')

    # Ensure the required files exist
    for required_file in [modlist_html_file, manifest_json_file]:
        if not os.path.isfile(required_file):
            print('ERROR: Required file not found: {f}'.format(f=required_file))
            return 2

    # Create the mod directory
    if not os.path.isdir(mod_file_dir):
        print('Creating directory: {d}'.format(d=mod_file_dir))
        os.makedirs(mod_file_dir, exist_ok=True)

    # Read the project info file
    try:
        mapping_data = read_project_info_file()
    except ModpackMakerError as exc:
        print('ERROR: Getting project mapping data\n{e}\n{t}'.format(e=str(exc), t=traceback.format_exc()))
        return 3

    # Get the list of required URLs
    try:
        required_mod_urls = read_modlist_html(modlist_html_file)
    except ModpackMakerError as exc:
        print('ERROR: Reading modlist HTML file: {f}\n{e}\n{t}'.format(
            f=modlist_html_file, e=str(exc), t=traceback.format_exc()))
        return 4

    # Read in the manifest file with the project IDs and download IDs
    try:
        manifest = read_manifest_json(manifest_json_file)
    except ModpackMakerError as exc:
        print('ERROR: Reading manifest.json file: {f}\n{e}\n{t}'.format(
            f=manifest_json_file, e=str(exc), t=traceback.format_exc()))
        return 5

    # Get the info for required projects from mapping
    try:
        projects, urls_not_found = get_forge_project_info_from_mapping(
            mapping_data=mapping_data, required_urls=required_mod_urls)
    except ModpackMakerError as exc:
        print('ERROR: Getting project data from existing mappings\n{e}\n{t}'.format(
            f=manifest_json_file, e=str(exc), t=traceback.format_exc()))
        return 6

    # Query CurseForge for project info
    new_projects, urls_not_found = get_forge_project_ids_from_url_list(url_list=urls_not_found)

    # Add the new projects to the mapping data
    mapping_data += new_projects
    try:
        write_project_info_file(mapping_contents=mapping_data)
    except ModpackMakerError as exc:
        print('ERROR: Writing project mapping file: {f}\n{e}\n{t}'.format(
            f=mapping_file, e=str(exc), t=traceback.format_exc()))
        return 7

    # Combine the project data
    projects += new_projects

    # Generate download URLs
    download_urls, missing_projects = get_download_urls(manifest_data=manifest, project_data=projects)

    # Print the download URLs and missing projects
    for download_url in download_urls:
        print(download_url)

    # Download the mods
    failed_downloads = download_mods(download_urls=download_urls, download_directory=mod_file_dir)

    # Print the missing projects
    for missing_project in missing_projects:
        print('WARNING: Project not found: {n}'.format(n=missing_project['slug']))

    for failed_download in failed_downloads:
        print('WARNING: Failed download URL: {f}'.format(f=failed_download))

    print('Completed building the modpack: {d}'.format(d=mod_dir))
    return 0


def download_mods(download_urls, download_directory):
    """Download a list of mods from the provided URLs

    :param download_urls: (list) of string URLs
    :param download_directory: (str) directory to download mods to
    :return: (list) failed download URLs
    :raises: ModpackMakerError
    """
    print('Attempting to download [{n}] mods...'.format(n=str(len(download_urls))))

    # Exit if there are no download URLs
    if len(download_urls) < 1:
        print('No mods to download')
        return

    # Set up Firefox options to handle file download
    firefox_options = FirefoxOptions()
    firefox_options.set_preference("browser.download.folderList", 2)
    firefox_options.set_preference("browser.download.manager.showWhenStarting", False)
    firefox_options.set_preference("browser.download.dir", download_directory)
    firefox_options.set_preference("browser.helperApps.neverAsk.saveToDisk", "application/java-archive")

    # Create a Firefox WebDriver instance
    driver = webdriver.Firefox(options=firefox_options)

    # Store the problem download URLs
    failed_downloads = []

    # Count the downloads
    download_count = 1

    for download_url in download_urls:
        print('Downloading mod [{c}] of [{t}] from URL: {u}'.format(
            c=str(download_count), t=str(len(download_urls)), u=download_url))
        # Navigate to the web page and download
        try:
            driver.get(download_url)
        except Exception as exc:
            print('WARNING: Problem downloading from URL: {u}\n{e}'.format(u=download_url, e=str(exc)))
            failed_downloads.append(download_url)
            continue

        # Wait 30 seconds before the next mod
        print('Waiting 30 seconds to download the next mod...')
        time.sleep(30)

    # Quit the web driver
    print('Exiting the driver')
    driver.quit()

    print('Completed downloading mods')
    print('[{n}] downloads failed'.format(n=str(len(failed_downloads))))
    return failed_downloads


def get_download_urls(manifest_data, project_data):
    """Given the mod manifest and project data, generate download URLs

    :param manifest_data: (dict) manifest.json content
    :param project_data: (list) of dict project info
    :return: (list) of download URLs, and projects NOT found in manifest
    """
    print('Getting download URLs from combining manifest data and project data...')

    # Store the download URLs
    download_urls = []
    missing_projects = []
    client_mods = []

    for project in project_data:
        print('Generating download URL for project: {n}'.format(n=project['slug']))
        found = False
        for manifest_entry in manifest_data['files']:
            if 'projectID' not in manifest_entry.keys():
                print('WARNING: Missing projectID in manifest entry: {d}'.format(d=str(manifest_entry)))
                continue
            if 'fileID' not in manifest_entry.keys():
                print('WARNING: Missing fileID in manifest entry: {d}'.format(d=str(manifest_entry)))
                continue
            if str(manifest_entry['projectID']) == str(project['project_id']):
                if project['client_mod']:
                    print('Skipping client mod: {n}'.format(n=project['slug']))
                    client_mods.append(project)
                    continue
                download_id = manifest_entry['fileID']
                print('Found download ID [{d}] for project: {n}'.format(d=str(download_id), n=project['slug']))
                download_url = 'https://www.curseforge.com/minecraft/mc-mods/{n}/download/{d}'.format(
                    n=project['slug'], d=str(download_id))
                print('Generated download URL: {d}'.format(d=download_url))
                download_urls.append(download_url)
                found = True
                break
        if not found:
            print('WARNING: Did not find a manifest entry for project: {n}'.format(n=project['slug']))
            missing_projects.append(project)

    print('Found [{n}] download URLs'.format(n=str(len(download_urls))))
    if len(missing_projects) > 0:
        print('WARNING: [{n}] projects not found in the manifest'.format(n=str(len(missing_projects))))
    return download_urls, missing_projects


def get_forge_project_info_from_mapping(mapping_data, required_urls):
    """Given mapping data and a URL, return the project info

    :param mapping_data: (list) of dict mapping data
    :param required_urls: (list) of string URLs requred
    :return: (tuple) (list) info about each project, (list) of URLs not found in mapping data
    """
    print('Checking mapping data for [{n}] URLs'.format(n=str(len(required_urls))))

    # Store the project list, and non-found URL list
    projects = []
    non_found_urls = []

    for required_url in required_urls:
        found = False
        print('Checking mapping data for URL: {u}'.format(u=required_url))
        for project_in_mapping in mapping_data:
            if project_in_mapping['url'] == required_url:
                print('Found mapping data for URL: {u}'.format(u=required_url))
                projects.append(project_in_mapping)
                found = True
                break
        if not found:
            print('Mapping data not found for URL: {u}'.format(u=required_url))
            non_found_urls.append(required_url)

    # Return data
    print('Found [{n}] projects in mapping data'.format(n=str(len(projects))))
    print('Did not find [{n}] URLs in mapping data'.format(n=str(len(non_found_urls))))
    return projects, non_found_urls


def get_forge_project_id_from_url(driver, url):
    """Given a Forge MineCraft mod URL, get the project ID

    :param driver: () Selenium web driver object
    :param url: (str) CurseForge URL of a Forge mod
    :return: (str) Project ID or None when not found
    :raises: ModpackMakerError
    """
    print('Attempting to retrieve the project ID from URL: {u}'.format(u=url))
    driver.get(url)

    # Wait for the element to be present (timeout after 10 seconds)
    try:
        WebDriverWait(driver, 10).until(exp_cond.presence_of_element_located((By.XPATH, xpath_expression)))
    except TimeoutException as exc:
        msg = 'TimeoutException: The element [{x}] was not found within the specified time at URL [{u}]\n{e}'.format(
            x=xpath_expression, u=url, e=str(exc))
        raise ModpackMakerError(msg) from exc

    # Get the project ID element
    try:
        project_id_element = driver.find_element(By.XPATH, xpath_expression)
    except NoSuchElementException as exc:
        msg = 'NoSuchElementException: The element [{x}] was not found at URL [{u}]\n{e}'.format(
            x=xpath_expression, u=url, e=str(exc))
        raise ModpackMakerError(msg) from exc

    # Set and return project ID
    project_id = project_id_element.text
    print("Project ID: {p}".format(p=project_id))
    return project_id


def get_forge_project_ids_from_url_list(url_list):
    """Given a list of URLs, return a list of dict project info containing the project IDs

    :param url_list: (list) of string URLs to retrieve project IDs for
    :return: (tuple) list of dict project info, list of URLs unable to obtain info for
    """
    # Store the return data
    projects = []
    non_found_urls = []

    # Exit if the list is empty to avoid starting up the driver
    if len(url_list) < 1:
        return projects, non_found_urls

        # Start up the Firefox web driver
    driver = webdriver.Firefox()

    for url in url_list:
        try:
            project_id = get_forge_project_id_from_url(driver=driver, url=url)
        except ModpackMakerError as exc:
            print('ERROR: Problem getting mod from URL: {u}\n{e}\n{t}'.format(
                u=url, e=str(exc), t=traceback.format_exc()))
            non_found_urls.append(url)
            continue
        url_parts = url.split('/')
        if len(url_parts) < 6:
            print('ERROR: Unable to determine project slug from URL: {u}'.format(u=url))
            non_found_urls.append(url)
        else:
            # Get the project slug
            project_slug = url_parts[5]
            # Timestamp for the update
            update_time = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
            projects.append({
                'client_mod': False,
                'project_id': project_id,
                'slug': project_slug,
                'updated': update_time,
                'url': url
            })

    print('Quitting the Firefox driver...')
    driver.quit()
    print('Found info for [{n}] projects'.format(n=str(len(projects))))
    print('Did not find info for [{n}] required mod URLs'.format(n=str(len(non_found_urls))))
    return projects, non_found_urls


def read_manifest_json(manifest_json_path):
    """Reads in the manifest.json file

    :param manifest_json_path: (str) path to the manifest.json file
    :return: (dict) containing the manifest JSON data
    """
    print('Attempting to read in the manifest.json file: {f}'.format(f=manifest_json_path))

    # Ensure the manifest json exists
    if not os.path.isfile(manifest_json_path):
        msg = 'manifest.json file not found: {f}'.format(f=manifest_json_path)
        raise ModpackMakerError(msg)

    # Read the file
    try:
        with open(manifest_json_path, 'r') as f:
            file_content = f.read()
        json_content = json.loads(file_content)
    except Exception as exc:
        msg = 'Problem loading JSON from file: {f}'.format(f=manifest_json_path)
        raise ModpackMakerError(msg) from exc

    # Validate the content
    if 'files' not in json_content.keys():
        msg = 'files not found in manifest.json content: {d}'.format(d=str(json_content))
        raise ModpackMakerError(msg)
    if not isinstance(json_content['files'], list):
        msg = 'Expected a list for files in json content, but found: {t}'.format(t=type(json_content['files']))
        raise ModpackMakerError(msg)
    return json_content


def read_modlist_html(modlist_html_path):
    """Read the modlist HTML file and generate a list of mod URLs

    :param modlist_html_path: (str) Path to the modlist html file
    :return: (list) of string mod URLs
    """
    print('Attempting to read modlist html file: {f}'.format(f=modlist_html_path))

    # Ensure the modpack file exists
    if not os.path.isfile(modlist_html_path):
        msg = 'Modlist html file not found: {f}'.format(f=modlist_html_path)
        raise ModpackMakerError(msg)

    # Read the file
    with open(modlist_html_path) as f:
        modlist_html_lines = f.readlines()

    # Store the required URLs
    required_urls = []

    # Get URLs from each line
    for modlist_html_line in modlist_html_lines:
        if modlist_html_line.startswith('<li><a href="https://www.curseforge.com/minecraft/mc-mods'):
            parts = modlist_html_line.split('"')
            if len(parts) < 2:
                print('WARNING: This line is an unexpected format: {f}'.format(f=modlist_html_line))
                continue
            required_urls.append(parts[1])
    print('Found [{n}] mods in file: {f}'.format(n=str(len(required_urls)), f=modlist_html_path))
    return required_urls


def read_project_info_file():
    """Read the project info file and returns a list of dicts containing the info

    :return: (list) of dict info about each project, including the URL and ID
    :raises: ModpackMakerError
    """
    # Return an empty list if the file does not exist
    if not os.path.isfile(mapping_file):
        print('Mapping file not found: {f}'.format(f=mapping_file))
        return []

    # Load the JSON content
    print('Reading the mapping file: {f}'.format(f=mapping_file))
    try:
        with open(mapping_file, 'r') as f:
            json_content = f.read()
        mapping_contents = json.loads(json_content)
    except Exception as exc:
        msg = 'Problem loading JSON from file: {f}'.format(f=mapping_file)
        raise ModpackMakerError(msg) from exc
    if not isinstance(mapping_contents, list):
        msg = 'Expected the content of file [{f}] to be type list, found: {t}'.format(
            f=mapping_file, t=type(mapping_contents))
        raise ModpackMakerError(msg)
    return mapping_contents


def write_project_info_file(mapping_contents):
    """Writes a list of the project URL to ID mapping to file

    :param mapping_contents: (list) of  project info dicts
    :return: None
    :raises: ModpackMakerError
    """
    if not isinstance(mapping_contents, list):
        raise ModpackMakerError('mapping_contents arg must be a list, found: {t}'.format(
            t=type(mapping_contents)))

    if not os.path.isdir(minecraft_dir):
        print('Creating directory: {d}'.format(d=minecraft_dir))
        os.makedirs(minecraft_dir, exist_ok=True)

    # Get JSON content
    json_content = json.dumps(mapping_contents, indent=2, sort_keys=False)

    # Overwrite the mega completion file
    try:
        with open(mapping_file, 'w') as f:
            f.write(json_content)
    except (IOError, OSError) as exc:
        msg = 'Problem writing mapping file: {f}'.format(f=mapping_file)
        raise ModpackMakerError(msg) from exc


def main():
    parser = argparse.ArgumentParser(description='modpack maker command line interface (CLI)')
    parser.add_argument('command', help='mantis command')
    parser.add_argument('--mod', help='Directory for the extracted mod pack', required=True)
    args = parser.parse_args()

    # Get the command
    command = args.command.strip()

    valid_commands_str = ','.join(valid_commands)
    if command not in valid_commands:
        print('Invalid command found [{c}]\n'.format(c=command) + valid_commands_str)
        return 1

    res = 0
    if command == 'build':
        res = build(args)
    return res


if __name__ == '__main__':
    exit_code = main()
    sys.exit(exit_code)
